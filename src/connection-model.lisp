; paredit:ignore-file length-emptiness-test -- HOST is a string; LENGTH is the portable emptiness check and CONSP is not equivalent.
(in-package #:redis-kit)

(defclass redis-connection ()
  ((host
    :initarg :host
    :reader connection-host)
   (port
    :initarg :port
    :reader connection-port)
   (protocol
    :initarg :protocol
    :accessor connection-protocol)
   (timeout
    :initarg :timeout
    :reader connection-timeout)
   (connect-timeout
    :initarg :connect-timeout
    :reader %connection-connect-timeout)
   (read-timeout
    :initarg :read-timeout
    :reader %connection-read-timeout)
   (username
    :initarg :username
    :reader %connection-username)
   (password
    :initarg :password
    :reader %connection-password)
   (database
    :initarg :database
    :reader %connection-database)
   (handshake-p
    :initarg :handshake
    :reader %connection-handshake-p)
   (tls
     :initarg :tls
     :reader connection-tls)
   (retry-policy
     :initarg :retry-policy
     :reader connection-retry-policy)
   (push-handler
    :initarg :push-handler
    :reader %connection-push-handler)
   (max-pushes
    :initarg :max-pushes
    :reader %connection-max-pushes)
   (socket
    :initform nil
    :accessor %connection-socket)
   (stream
    :initform nil
    :accessor %connection-stream)
   (state
    :initform :new
    :accessor connection-state)
   (lock
    :initarg :lock
    :reader %connection-lock)
   (network-boundary
    :accessor connection-network-boundary)
   (custom-boundary-p
     :initarg :custom-boundary-p
     :reader %connection-custom-boundary-p)
   (metrics
     :initarg :metrics
     :reader %connection-metrics)
   (pushes
    :initform nil
    :accessor %connection-pushes)))

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

(defun make-connection (&key
                               (host "127.0.0.1")
                               (port 6379)
                               (protocol :resp3)
                               (timeout 5)
                               (connect-timeout nil connect-timeout-supplied-p)
                               (read-timeout nil read-timeout-supplied-p)
                               username
                               password
                               database
                               (handshake t)
                                network-boundary
                                tls
                                retry-policy
                                metric-registry
                                push-handler
                               (max-pushes 1024))
  "Create a Redis connection.

The network boundary is always represented by CL-BOUNDARY-KIT.  Without a
caller-supplied boundary its request function is backed by a usocket stream;
tests and applications can inject a boundary without opening a socket."
  (unless (and (stringp host) (plusp (length host)))
    (error 'redis-client-error :message "HOST must be a non-empty string."
           :cause host))
  (unless (and (integerp port) (<= 0 port 65535))
    (error 'redis-client-error :message "PORT must be an integer in [0, 65535]."
           :cause port))
  (%validate-protocol protocol)
  (%validate-non-negative-number timeout "TIMEOUT")
  (unless connect-timeout-supplied-p
    (setf connect-timeout timeout))
  (unless read-timeout-supplied-p
    (setf read-timeout timeout))
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
