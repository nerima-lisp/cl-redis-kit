(in-package #:redis-kit)

(defmethod %call-with-command-policy
    ((connection redis-connection) command thunk retry-safe-p)
  (if (and retry-safe-p (connection-retry-policy connection))
      (cl-resilience-kit:call-with-resilience
       thunk
       :retry-policy (connection-retry-policy connection)
       :operation command)
      (funcall thunk)))
