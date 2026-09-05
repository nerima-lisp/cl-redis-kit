; paredit:ignore-file length-emptiness-test -- HOST is a string; LENGTH is the portable emptiness check and CONSP is not equivalent.
(defun redis-connection-p (object)
  (typep object 'redis-connection))

(defun %validate-non-negative-number (value name)
  (unless (or (null value)
              (and (realp value) (not (minusp value))))
    (error 'redis-client-error
           :message (format nil "~A must be NIL or a non-negative real number."
                            name)
           :cause value))
  value)

(defun %validate-protocol (protocol)
  (unless (member protocol '(:resp2 :resp3) :test #'eq)
    (error 'redis-client-error
           :message "PROTOCOL must be :RESP2 or :RESP3."
           :cause protocol))
  protocol)

(defun %validate-database (database)
  (unless (or (null database)
              (and (integerp database) (not (minusp database))))
    (error 'redis-client-error
           :message "DATABASE must be NIL or a non-negative integer."
           :cause database))
  database)

(defun make-connection (&rest arguments
                        &key host port protocol timeout
                          connect-timeout read-timeout username password
                          database handshake network-boundary tls retry-policy
                          metric-registry push-handler max-pushes)
  "Create a Redis connection.

The network boundary is always represented by CL-BOUNDARY-KIT.  Without a
  caller-supplied boundary its request function is backed by a usocket stream;
  tests and applications can inject a boundary without opening a socket."
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
  (unless (and (stringp host) (plusp (length host)))
    (error 'redis-client-error :message "HOST must be a non-empty string."
           :cause host))
  (unless (and (integerp port) (<= 0 port 65535))
    (error 'redis-client-error :message "PORT must be an integer in [0, 65535]."
           :cause port))
  (%validate-protocol protocol)
  (%validate-non-negative-number timeout "TIMEOUT")
  (%validate-non-negative-number connect-timeout "CONNECT-TIMEOUT")
  (%validate-non-negative-number read-timeout "READ-TIMEOUT")
  (%validate-database database)
  (%validate-tls-options tls)
  (unless (and (integerp max-pushes) (not (minusp max-pushes)))
    (error 'redis-client-error
           :message "MAX-PUSHES must be a non-negative integer."
           :cause max-pushes))
  (let* ((connection
           (make-instance 'redis-connection
                          :host host
                          :port port
                          :protocol protocol
                          :timeout timeout
                          :connect-timeout connect-timeout
                          :read-timeout read-timeout
                          :username username
                          :password password
                          :database database
                          :handshake handshake
                          :tls tls
                           :retry-policy retry-policy
                           :metrics (and metric-registry
                                         (make-redis-metrics
                                          :registry metric-registry))
                           :push-handler push-handler
                          :max-pushes max-pushes
                          :lock (cl-concurrent-kit:make-lock
                                  :name "redis-connection")
                          :custom-boundary-p (not (null network-boundary))))
         (boundary
           (or network-boundary
               (cl-boundary-kit:make-network-boundary
                :request-fn
                (lambda (request &key timeout)
                  (%socket-boundary-request connection request timeout))))))
    (setf (connection-network-boundary connection) boundary)
    connection))
