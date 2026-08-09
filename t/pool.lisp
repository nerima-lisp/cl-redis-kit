; paredit:ignore-file leftover-inspect-call -- CL-WEAVE's DESCRIBE is the BDD test DSL, not a debugger inspection call.
(in-package #:redis-kit/test)

(describe
    "connection pool"
  (it "bounds connections and returns them after borrowing"
    (let ((pool (redis-kit:make-pool
                 :protocol :resp2
                 :handshake nil
                 :network-boundary (make-test-boundary)
                 :max-size 1
                 :max-wait 1)))
      (unwind-protect
           (progn
             (expect (redis-kit:pool-size pool) :to-be 0)
             (expect (redis-kit:pool-execute pool "PING") :to-equal "PONG")
             (expect (redis-kit:pool-size pool) :to-be 1)
             (expect (redis-kit:pool-idle-count pool) :to-be 1)
             (redis-kit:with-pool (connection pool)
               (expect (redis-kit:ping connection) :to-equal "PONG"))
             (expect (redis-kit:pool-idle-count pool) :to-be 1)
             (redis-kit:close-pool pool)
             (expect (redis-kit:pool-closed-p pool) :to-be t)
             (expect (redis-kit:pool-size pool) :to-be 0))
        (redis-kit:close-pool pool))))

  (it "rolls back a reserved slot when opening a connection fails"
    (let ((pool (redis-kit:make-pool
                 :protocol :resp3
                 :network-boundary
                 (cl-boundary-kit:make-network-boundary
                  :request-fn
                  (lambda (request &key timeout)
                    (declare (ignore request timeout))
                    (error "synthetic open failure")))
                 :max-size 1
                 :max-wait 0.01)))
      (unwind-protect
           (progn
             (signals redis-kit:redis-connection-error
               (redis-kit:pool-execute pool "PING"))
             (expect (redis-kit:pool-size pool) :to-be 0)
             (expect (redis-kit:pool-idle-count pool) :to-be 0))
        (redis-kit:close-pool pool))))

  (it "times out when every connection is borrowed"
    (let ((pool (redis-kit:make-pool
                 :protocol :resp2
                 :handshake nil
                 :network-boundary (make-test-boundary)
                 :max-size 1
                 :max-wait 0)))
      (unwind-protect
           (redis-kit:pool-with-connection
            pool
            (lambda (connection)
              (declare (ignore connection))
              (signals redis-kit:redis-timeout-error
                (redis-kit:pool-with-connection
                 pool
                 (lambda (nested-connection)
                   (declare (ignore nested-connection))
                   :unreachable)))))
        (redis-kit:close-pool pool)))))
