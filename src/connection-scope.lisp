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
