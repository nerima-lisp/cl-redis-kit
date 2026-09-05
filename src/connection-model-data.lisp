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
