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

(defun make-pool (&rest arguments
                  &key host port protocol timeout connect-timeout read-timeout
                    username password database handshake network-boundary tls
                    retry-policy metric-registry push-handler max-pushes
                    max-size max-wait)
  "Create a bounded pool of lazily opened Redis connections.

MAX-SIZE counts both idle and borrowed connections.  MAX-WAIT is NIL for an
unbounded wait, or a non-negative number of seconds for callers waiting for a
slot.  A connection is opened outside the pool lock after its slot is
  reserved, so a slow connect does not block borrowers that already have idle
  connections."
  (unless (%keyword-supplied-p arguments :host)
    (setf host "127.0.0.1"))
  (unless (%keyword-supplied-p arguments :port)
    (setf port 6379))
  (unless (%keyword-supplied-p arguments :protocol)
    (setf protocol :resp3))
  (unless (%keyword-supplied-p arguments :timeout)
    (setf timeout 5))
  (unless (%keyword-supplied-p arguments :connect-timeout)
    (setf connect-timeout timeout))
  (unless (%keyword-supplied-p arguments :read-timeout)
    (setf read-timeout timeout))
  (unless (%keyword-supplied-p arguments :handshake)
    (setf handshake t))
  (unless (%keyword-supplied-p arguments :max-pushes)
    (setf max-pushes 1024))
  (unless (%keyword-supplied-p arguments :max-size)
    (setf max-size 8))
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

(defun %pool-reservation-accepted-p (pool)
  (cl-concurrent-kit:with-lock-held ((%pool-lock pool))
    (if (%pool-closed-p pool)
        (progn
          (decf (%pool-size pool))
          (cl-concurrent-kit:condition-notify (%pool-condition pool))
          nil)
        t)))

(defun %pool-reservation-failed (pool cause)
  (cl-concurrent-kit:with-lock-held ((%pool-lock pool))
    (decf (%pool-size pool))
    (cl-concurrent-kit:condition-notify (%pool-condition pool)))
  (error cause))
