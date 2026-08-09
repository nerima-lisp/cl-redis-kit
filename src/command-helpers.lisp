(in-package #:redis-kit)

(defun %command-value (connection command arguments &key (decode :utf-8)
                                                   timeout retry-safe-p)
  (reply-value (%execute-command connection command arguments
                                 :timeout timeout
                                 :retry-safe-p retry-safe-p)
               :decode decode))

(defun %require-values (values name)
  (unless values
    (error 'redis-client-error
           :message (format nil "~A requires at least one value." name)
           :cause values))
  values)

(defun %require-even-values (values name)
  (unless (and values (evenp (length values)))
    (error 'redis-client-error
           :message (format nil "~A requires a non-empty even number of values."
                            name)
           :cause values))
  values)

(defun %require-key-values (key values name)
  (cons key (%require-values values name)))

(defun %one-expiration (options)
  (let ((present (remove nil (mapcar (lambda (entry)
                                      (when (getf options entry) entry))
                                    '(:ex :px :exat :pxat)))))
    (when (> (length present) 1)
      (error 'redis-client-error
             :message "Only one Redis expiration option may be supplied."
             :cause present))))

(defun %single-command-argument (arguments name)
  (multiple-value-bind (values options)
      (%split-options arguments '(:timeout :retry-safe-p))
    (when (> (length values) 1)
      (error 'redis-client-error
             :message (format nil "~A accepts at most one Redis argument." name)
             :cause values))
    (values values options)))
