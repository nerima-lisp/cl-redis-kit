(in-package #:redis-kit)

(defun %pool-acquire (pool wait)
  (%validate-pool pool)
  (%validate-pool-wait wait)
  (let ((deadline (%pool-deadline wait)))
    (loop
      (let ((connection nil)
            (reserve-p nil))
        (cl-concurrent-kit:with-lock-held ((%pool-lock pool))
          (when (%pool-closed-p pool)
            (error 'redis-connection-error
                   :message "The Redis pool has been closed."))
          (cond
            ((%pool-idle pool)
             (setf connection (pop (%pool-idle pool))))
            ((< (%pool-size pool) (pool-max-size pool))
             (incf (%pool-size pool))
             (setf reserve-p t))
            (t
             (let ((remaining (%pool-remaining deadline)))
               (when (and remaining (<= remaining 0))
                 (%pool-wait-timeout wait))
               (unless
                   (cl-concurrent-kit:condition-wait
                    (%pool-condition pool)
                    (%pool-lock pool)
                    :timeout remaining)
                 (%pool-wait-timeout wait))))))
        (cond
          ((and connection (eq (connection-state connection) :closed))
           (close-connection connection)
           (cl-concurrent-kit:with-lock-held ((%pool-lock pool))
             (decf (%pool-size pool))
             (cl-concurrent-kit:condition-notify (%pool-condition pool))))
          (connection
           (return connection))
          (reserve-p
           (handler-case
               (let ((new-connection
                       (apply #'make-connection
                              (%pool-connection-arguments pool))))
                 (open-connection new-connection)
                 (return new-connection))
             (error (cause)
               (%pool-reservation-failed pool cause)))))))))

(defun %pool-release (pool connection)
  (let ((close-p nil))
    (cl-concurrent-kit:with-lock-held ((%pool-lock pool))
      (if (or (%pool-closed-p pool)
              (eq (connection-state connection) :closed))
          (progn
            (decf (%pool-size pool))
            (setf close-p t)
            (cl-concurrent-kit:condition-notify (%pool-condition pool)))
          (progn
            (push connection (%pool-idle pool))
            (cl-concurrent-kit:condition-notify (%pool-condition pool)))))
    (when close-p
      (close-connection connection)))
  connection)

(defun call-with-pool-connection (pool thunk &key (timeout nil timeoutp))
  "Borrow a connection, call THUNK with it, and always return it.

When TIMEOUT is omitted, POOL-MAX-WAIT controls waiting.  Supplying
`:timeout nil` explicitly requests an unbounded wait."
  (%validate-pool pool)
  (unless (functionp thunk)
    (error 'redis-client-error
           :message "THUNK must be a function."
           :cause thunk))
  (let ((connection (%pool-acquire pool
                                   (if timeoutp timeout (pool-max-wait pool)))))
    (unwind-protect
        (funcall thunk connection)
      (%pool-release pool connection))))

(defun pool-with-connection (pool thunk &key (timeout nil timeoutp))
  "Call THUNK with a borrowed connection and always return the connection."
  (if timeoutp
      (call-with-pool-connection pool thunk :timeout timeout)
      (call-with-pool-connection pool thunk)))

(defun close-pool (pool)
  "Close POOL and all idle connections.

Borrowed connections are closed as each borrower returns them.  Calling this
function more than once is harmless."
  (%validate-pool pool)
  (let ((idle nil))
    (cl-concurrent-kit:with-lock-held ((%pool-lock pool))
      (unless (%pool-closed-p pool)
        (setf (%pool-closed-p pool) t
              idle (%pool-idle pool)
              (%pool-idle pool) nil)
        (decf (%pool-size pool) (length idle))
        (cl-concurrent-kit:condition-broadcast (%pool-condition pool))))
    (dolist (connection idle)
      (close-connection connection)))
  pool)

(defun pool-execute (pool command &rest arguments)
  "Execute COMMAND using a borrowed connection from POOL.

COMMAND arguments, including `:decode` and `:timeout`, are passed to EXECUTE;
the pool's MAX-WAIT controls only acquisition."
  (pool-with-connection
   pool
   (lambda (connection)
     (apply #'execute connection command arguments))))

(defmacro with-pool ((variable pool &key (timeout nil timeoutp)) &body body)
  "Borrow VARIABLE from POOL for BODY and return it afterward."
  (if timeoutp
      `(pool-with-connection ,pool
                             (lambda (,variable) ,@body)
                             :timeout ,timeout)
      `(pool-with-connection ,pool
                             (lambda (,variable) ,@body))))
