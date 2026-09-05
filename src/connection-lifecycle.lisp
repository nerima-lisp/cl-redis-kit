(defun %perform-handshake (connection)
  (when (%connection-handshake-p connection)
    (when (eq (connection-protocol connection) :resp3)
      (handler-case
          (%with-command-journal ("HELLO" 1)
            (%check-server-reply
             (%raw-command connection "HELLO" '(3)
                           :timeout (connection-timeout connection))))
        (redis-server-error (condition)
          (if (%unsupported-hello-error-p condition)
              (setf (connection-protocol connection) :resp2)
              (error condition)))))
    (when (%connection-password connection)
      (let ((arguments
              (if (%connection-username connection)
                  (list (%connection-username connection)
                        (%connection-password connection))
                  (list (%connection-password connection)))))
        (%with-command-journal ("AUTH" (length arguments))
          (%check-server-reply
           (%raw-command connection "AUTH" arguments
                         :timeout (connection-timeout connection))))))
    (when (%connection-database connection)
      (%with-command-journal ("SELECT" 1)
        (%check-server-reply
         (%raw-command connection "SELECT"
                       (list (%connection-database connection))
                       :timeout (connection-timeout connection))))))
  connection)

(defun %open-connection-under-lock (connection)
  (case (connection-state connection)
    (:ready (return-from %open-connection-under-lock connection))
    (:opening (return-from %open-connection-under-lock connection))
    (:closed (error 'redis-connection-error
                    :message "The Redis connection has been closed."))
    (otherwise nil))
  (setf (connection-state connection) :opening)
  (handler-case
      (progn
        (%call-with-timeout connection (%connection-connect-timeout connection)
                             (lambda () (%establish-transport connection)))
        (%perform-handshake connection)
        (setf (connection-state connection) :ready)
        connection)
    (redis-error (condition)
      (%invalidate-connection connection)
      (error condition))
    (error (cause)
      (%invalidate-connection connection)
      (error 'redis-connection-error
             :message "Unable to open the Redis connection."
             :cause cause))))

(defun open-connection (connection)
  "Open CONNECTION and perform its optional HELLO/AUTH/SELECT handshake."
  (unless (redis-connection-p connection)
    (error 'redis-client-error :message "Expected a Redis connection."
           :cause connection))
  (cl-concurrent-kit:with-lock-held ((%connection-lock connection))
    (%open-connection-under-lock connection)))

(defun close-connection (connection)
  "Close CONNECTION.  A closed connection cannot be reopened."
  (unless (redis-connection-p connection)
    (error 'redis-client-error :message "Expected a Redis connection."
           :cause connection))
  (cl-concurrent-kit:with-lock-held ((%connection-lock connection))
    (%close-transport connection)
    (setf (connection-state connection) :closed))
  connection)

(defun connection-open-p (connection)
  (and (redis-connection-p connection)
       (eq (connection-state connection) :ready)))

(defun connection-metric-registry (connection)
  "Return the observability registry attached to CONNECTION, if any."
  (unless (redis-connection-p connection)
    (error 'redis-client-error
           :message "Expected a Redis connection."
           :cause connection))
  (let ((metrics (%connection-metrics connection)))
    (and metrics
         (redis-metrics-registry metrics))))

(defun connection-metrics-snapshot (connection)
  "Return the attached metrics snapshot, or NIL when metrics are disabled."
  (unless (redis-connection-p connection)
    (error 'redis-client-error
           :message "Expected a Redis connection."
           :cause connection))
  (let ((metrics (%connection-metrics connection)))
    (and metrics
         (redis-metrics-snapshot metrics))))
