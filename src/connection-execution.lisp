(in-package #:redis-kit)

(defgeneric %call-with-command-policy
    (connection command thunk retry-safe-p)
  (:documentation
   "Run a command through the configured retry policy when available.

The core system deliberately does not require a resilience implementation.
The optional CL-REDIS-KIT/RESILIENCE system specializes this operation with
CL-RESILIENCE-KIT; the core method fails explicitly when retrying was
requested without that integration loaded."))

(defmethod %call-with-command-policy
    ((connection redis-connection) command thunk retry-safe-p)
  (if (and (connection-retry-policy connection)
           retry-safe-p)
      (error 'redis-client-error
             :message
             "Retry-safe execution requires the cl-redis-kit/resilience system."
             :cause command)
      (funcall thunk)))

(defun %execute-command (connection command arguments
                         &key timeout retry-safe-p)
  (open-connection connection)
  (cl-concurrent-kit:with-lock-held ((%connection-lock connection))
    (with-command-metrics (metrics (%connection-metrics connection))
      (%call-with-command-policy
       connection
       command
       (lambda ()
         (%open-connection-under-lock connection)
         (%check-server-reply
          (%raw-command connection command arguments :timeout timeout)))
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

(defun %execute-pipeline-once (connection commands timeout)
  (mapcar #'%check-server-reply
          (%request-replies connection (encode-commands commands)
                            (length commands) timeout)))

(defun pipeline-replies (connection commands &key timeout retry-safe-p)
  "Execute COMMANDS and return typed replies in order.

PIPELINE-REPLIES is retryable only when RETRY-SAFE-P is true because a
partially written pipeline may have already changed server state."
  (unless (and (listp commands) commands)
    (error 'redis-client-error
           :message "PIPELINE-REPLIES requires a non-empty command list."
           :cause commands))
  (dolist (command commands)
    (unless (and (listp command) (consp command))
      (error 'redis-client-error
             :message "Each pipeline command must be a non-empty list."
             :cause command)))
  (open-connection connection)
  (cl-concurrent-kit:with-lock-held ((%connection-lock connection))
    (with-command-metrics (metrics (%connection-metrics connection))
      (%call-with-command-policy
       connection
       "PIPELINE"
       (lambda ()
         (%open-connection-under-lock connection)
         (%execute-pipeline-once connection commands timeout))
       retry-safe-p))))

(defun pipeline (connection commands &key timeout retry-safe-p)
  (pipeline-replies connection commands
                    :timeout timeout
                    :retry-safe-p retry-safe-p))

(defun drain-pushes (connection)
  "Return queued RESP3 push replies in arrival order and clear the queue."
  (unless (redis-connection-p connection)
    (error 'redis-client-error :message "Expected a Redis connection."
           :cause connection))
  (cl-concurrent-kit:with-lock-held ((%connection-lock connection))
    (prog1 (nreverse (%connection-pushes connection))
      (setf (%connection-pushes connection) nil))))

(defun call-with-connection (connection thunk)
  "Open CONNECTION, call THUNK with it, and always close the connection.

THUNK is the continuation for the scoped connection.  Keeping the resource
boundary as a function makes it usable from higher-order code while the
WITH-CONNECTION macro remains a readable declaration for ordinary code."
  (unless (redis-connection-p connection)
    (error 'redis-client-error
           :message "Expected a Redis connection."
           :cause connection))
  (unless (functionp thunk)
    (error 'redis-client-error
           :message "THUNK must be a function."
           :cause thunk))
  (unwind-protect
       (progn
         (open-connection connection)
         (funcall thunk connection))
    (close-connection connection)))

(defmacro with-connection ((variable &rest initargs) &body body)
  `(call-with-connection
    (make-connection ,@initargs)
    (lambda (,variable) ,@body)))
