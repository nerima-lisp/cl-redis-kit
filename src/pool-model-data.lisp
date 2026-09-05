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
