(defun %execute-pipeline-once (connection commands timeout)
  (%with-command-journal ("PIPELINE" (length commands))
    (mapcar #'%check-server-reply
            (%request-replies connection (encode-commands commands)
                              (length commands) timeout))))

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
  (let ((effective-timeout (%effective-operation-timeout connection timeout)))
    (open-connection connection)
    (with-command-metrics (metrics (%connection-metrics connection))
      (%call-with-command-policy/k
       connection
       "PIPELINE"
       (lambda ()
         (cl-concurrent-kit:with-lock-held ((%connection-lock connection))
           (%open-connection-under-lock connection)
           (%execute-pipeline-once connection commands effective-timeout)))
       #'values
       #'error
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
