(in-package #:redis-kit)

(defclass redis-pool ()
  ((connection-arguments
    :initarg :connection-arguments
    :reader %pool-connection-arguments)
   (max-size
    :initarg :max-size
    :reader pool-max-size)
   (max-wait
    :initarg :max-wait
    :reader pool-max-wait)
   (idle
    :initform nil
    :accessor %pool-idle)
   (size
    :initform 0
    :accessor %pool-size)
   (lock
    :initarg :lock
    :reader %pool-lock)
   (condition
    :initarg :condition
    :reader %pool-condition)
   (closed-p
    :initform nil
    :accessor %pool-closed-p)))

(defun redis-pool-p (object)
  (typep object 'redis-pool))

(defun %validate-pool (pool)
  (unless (redis-pool-p pool)
    (error 'redis-client-error
           :message "Expected a Redis pool."
           :cause pool))
  pool)

(defun %validate-pool-wait (value)
  (unless (or (null value)
              (and (realp value) (not (minusp value))))
    (error 'redis-client-error
           :message "MAX-WAIT must be NIL or a non-negative real number."
           :cause value))
  value)

(defun make-pool (&key
                        (host "127.0.0.1")
                        (port 6379)
                        (protocol :resp3)
                        (timeout 5)
                        connect-timeout
                        read-timeout
                        username
                        password
                        database
                        (handshake t)
                        network-boundary
                        tls
                        retry-policy
                        metric-registry
                        push-handler
                        (max-pushes 1024)
                        (max-size 8)
                        max-wait)
  "Create a bounded pool of lazily opened Redis connections.

MAX-SIZE counts both idle and borrowed connections.  MAX-WAIT is NIL for an
unbounded wait, or a non-negative number of seconds for callers waiting for a
slot.  A connection is opened outside the pool lock after its slot is
reserved, so a slow connect does not block borrowers that already have idle
connections."
  (unless (and (integerp max-size) (plusp max-size))
    (error 'redis-client-error
           :message "MAX-SIZE must be a positive integer."
           :cause max-size))
  (%validate-pool-wait max-wait)
  (make-instance
   'redis-pool
   :connection-arguments
   (list :host host
         :port port
         :protocol protocol
         :timeout timeout
         :connect-timeout connect-timeout
         :read-timeout read-timeout
         :username username
         :password password
         :database database
         :handshake handshake
         :network-boundary network-boundary
         :tls tls
         :retry-policy retry-policy
         :metric-registry metric-registry
         :push-handler push-handler
         :max-pushes max-pushes)
   :max-size max-size
   :max-wait max-wait
   :lock (cl-concurrent-kit:make-lock :name "redis-pool")
   :condition (cl-concurrent-kit:make-condition-variable
               :name "redis-pool-condition")))

(defun pool-size (pool)
  "Return the number of connections, idle or borrowed, in POOL."
  (%validate-pool pool)
  (cl-concurrent-kit:with-lock-held ((%pool-lock pool))
    (%pool-size pool)))

(defun pool-idle-count (pool)
  "Return the number of currently available connections in POOL."
  (%validate-pool pool)
  (cl-concurrent-kit:with-lock-held ((%pool-lock pool))
    (length (%pool-idle pool))))

(defun pool-closed-p (pool)
  "Return true when POOL no longer accepts borrowers."
  (%validate-pool pool)
  (cl-concurrent-kit:with-lock-held ((%pool-lock pool))
    (%pool-closed-p pool)))

(defun %pool-clock-seconds ()
  (/ (cl-boundary-kit:clock-monotonic cl-concurrent-kit:*clock*)
     internal-time-units-per-second))

(defun %pool-deadline (seconds)
  (when seconds
    (+ (%pool-clock-seconds) seconds)))

(defun %pool-remaining (deadline)
  (when deadline
    (- deadline (%pool-clock-seconds))))

(defun %pool-wait-timeout (wait)
  (error 'redis-timeout-error
         :message "Timed out waiting for an available Redis connection."
         :cause wait))

(defun %pool-reservation-failed (pool cause)
  (cl-concurrent-kit:with-lock-held ((%pool-lock pool))
    (decf (%pool-size pool))
    (cl-concurrent-kit:condition-notify (%pool-condition pool)))
  (error cause))

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
