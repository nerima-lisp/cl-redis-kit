(in-package #:redis-kit)

(defmethod %call-with-command-policy/k
    ((connection redis-connection) command thunk on-success on-error
     retry-safe-p)
  (if (and retry-safe-p (connection-retry-policy connection))
      (cl-resilience-kit:call-with-resilience/k
       thunk
       on-success
       on-error
       :retry-policy (connection-retry-policy connection)
       :operation command)
      (call-next-method)))
