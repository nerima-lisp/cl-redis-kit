(defmethod %call-with-command-policy/k
    ((connection redis-connection) command thunk on-success on-error
     retry-safe-p)
  (if (and (connection-retry-policy connection)
           retry-safe-p)
      (funcall on-error
               (make-condition
                'redis-client-error
                :message
                "Retry-safe execution requires the cl-redis-kit/resilience system."
                :cause command))
      (multiple-value-bind (values condition)
          (handler-case
              (values (multiple-value-list (funcall thunk)) nil)
            (error (condition)
              (values nil condition)))
        (if condition
            (funcall on-error condition)
            (apply on-success values)))))

(defun %execute-command (connection command arguments
                         &key timeout retry-safe-p)
  (let ((effective-timeout (%effective-operation-timeout connection timeout)))
    (open-connection connection)
    (with-command-metrics (metrics (%connection-metrics connection))
      (%call-with-command-policy/k
       connection
       command
       (lambda ()
         (cl-concurrent-kit:with-lock-held ((%connection-lock connection))
           (%open-connection-under-lock connection)
           (%with-command-journal (command (length arguments))
             (%check-server-reply
              (%raw-command connection command arguments
                            :timeout effective-timeout)))))
       #'values
       #'error
       retry-safe-p))))

(defun %split-options (arguments option-names)
  (let ((values nil)
        (options nil)
        (remaining arguments)
        (option-set (make-hash-table :test #'eq)))
    (dolist (option option-names)
      (setf (gethash option option-set) t))
    (loop while remaining
          for item = (pop remaining)
          do (if (and (keywordp item) (gethash item option-set))
                 (if remaining
                     (setf (getf options item) (pop remaining))
                     (error 'redis-client-error
                            :message "A Redis option is missing its value."
                            :cause item))
                 (push item values)))
    (values (nreverse values) options)))

(defun execute-reply (connection command &rest arguments)
  "Execute COMMAND and return its typed REDIS-REPLY.

The optional :TIMEOUT and :RETRY-SAFE-P keywords are consumed by this client;
all other arguments are encoded as Redis command arguments.  Set
:RETRY-SAFE-P only when replaying COMMAND is safe for the application."
  (multiple-value-bind (command-arguments options)
      (%split-options arguments '(:timeout :retry-safe-p))
    (%execute-command connection command command-arguments
                      :timeout (getf options :timeout)
                      :retry-safe-p (getf options :retry-safe-p))))

(defun execute (connection command &rest arguments)
  "Execute COMMAND and convert its reply with REPLY-VALUE.

Use :DECODE NIL or :DECODE :RAW to preserve bulk octets, :TIMEOUT to
override the connection timeout, and :RETRY-SAFE-P to opt into retrying this
operation when the connection has a retry policy."
  (multiple-value-bind (command-arguments options)
      (%split-options arguments '(:decode :timeout :retry-safe-p))
    (reply-value
     (%execute-command connection command command-arguments
                       :timeout (getf options :timeout)
                       :retry-safe-p (getf options :retry-safe-p))
     :decode (getf options :decode :utf-8))))
