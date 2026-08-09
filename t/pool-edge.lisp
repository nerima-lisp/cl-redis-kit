; paredit:ignore-file leftover-inspect-call -- CL-WEAVE's DESCRIBE is the BDD test DSL, not a debugger inspection call.
(in-package #:redis-kit/test)

(describe
    "pool continuation boundaries"
  (it "returns borrowed connections after success and failure"
    (let ((pool (redis-kit:make-pool
                 :protocol :resp2
                 :handshake nil
                 :network-boundary (make-test-boundary)
                 :max-size 1
                 :max-wait 0)))
      (unwind-protect
           (progn
             (expect
              (redis-kit:call-with-pool-connection
               pool
               (lambda (connection) (redis-kit:ping connection))
               :timeout 0)
              :to-equal
              "PONG")
             (expect (redis-kit:pool-idle-count pool) :to-be 1)
             (signals error
               (redis-kit:call-with-pool-connection
                pool
                (lambda (connection)
                  (declare (ignore connection))
                  (error "synthetic borrower failure"))
                :timeout nil))
             (expect (redis-kit:pool-idle-count pool) :to-be 1))
        (redis-kit:close-pool pool))))

  (it "supports macro timeout and rejects invalid pool calls"
    (let ((pool (redis-kit:make-pool
                 :protocol :resp2
                 :handshake nil
                 :network-boundary (make-test-boundary)
                 :max-size 1
                 :max-wait 0)))
      (unwind-protect
           (progn
             (expect
              (redis-kit:with-pool (connection pool :timeout 0)
                (redis-kit:ping connection))
              :to-equal
              "PONG")
             (redis-kit:close-pool pool)
             (redis-kit:close-pool pool)
             (signals redis-kit:redis-connection-error
               (redis-kit:pool-execute pool "PING")))
        (redis-kit:close-pool pool)))
    (signals redis-kit:redis-client-error
      (redis-kit:make-pool :max-size 0))
    (signals redis-kit:redis-client-error
      (redis-kit:make-pool :max-size :not-an-integer))
    (signals redis-kit:redis-client-error
      (redis-kit:make-pool :max-wait -1))
    (signals redis-kit:redis-client-error
      (redis-kit:make-pool :max-wait :not-a-number))
    (signals redis-kit:redis-client-error
      (redis-kit:call-with-pool-connection nil #'identity))
    (let ((pool (redis-kit:make-pool
                 :protocol :resp2
                 :handshake nil
                 :network-boundary (make-test-boundary))))
      (unwind-protect
           (signals redis-kit:redis-client-error
             (redis-kit:call-with-pool-connection pool nil))
        (redis-kit:close-pool pool))))

  (it "discards a closed idle connection before replacing it"
    (let ((pool (redis-kit:make-pool
                 :protocol :resp2
                 :handshake nil
                 :network-boundary (make-test-boundary)
                 :max-size 1
                 :max-wait 0)))
      (unwind-protect
           (progn
             (expect (redis-kit:pool-execute pool "PING") :to-equal "PONG")
             (redis-kit:close-connection
              (first (redis-kit::%pool-idle pool)))
             (expect (redis-kit:pool-execute pool "PING") :to-equal "PONG")
             (expect (redis-kit:pool-size pool) :to-be 1)
             (expect (redis-kit:pool-idle-count pool) :to-be 1))
        (redis-kit:close-pool pool))))

  (it "times out after a condition wait reports no wakeup"
    (let ((pool (redis-kit:make-pool
                 :protocol :resp2
                 :handshake nil
                 :network-boundary (make-test-boundary)
                 :max-size 1)))
      (unwind-protect
           (let ((borrowed (redis-kit::%pool-acquire pool nil)))
             (unwind-protect
               (with-mocked-functions
                      (((symbol-function 'cl-concurrent-kit:condition-wait)
                        (lambda (&rest arguments)
                          (declare (ignore arguments))
                          nil)))
                    (signals redis-kit:redis-timeout-error
                      (redis-kit::%pool-acquire pool 1)))
             (let ((wait-calls 0))
               (with-mocked-functions
                   (((symbol-function 'cl-concurrent-kit:condition-wait)
                      (lambda (&rest arguments)
                        (declare (ignore arguments))
                        (incf wait-calls)
                        (= wait-calls 1))))
                 (signals redis-kit:redis-timeout-error
                   (redis-kit::%pool-acquire pool 1))))
               (redis-kit::%pool-release pool borrowed)))
        (redis-kit:close-pool pool))))

  (it "closes a borrowed connection after the pool closes"
    (let ((pool (redis-kit:make-pool
                 :protocol :resp2
                 :handshake nil
                 :network-boundary (make-test-boundary)
                 :max-size 1
                 :max-wait 0))
          (size-during-close nil))
      (unwind-protect
           (redis-kit:call-with-pool-connection
            pool
            (lambda (connection)
              (declare (ignore connection))
              (redis-kit:close-pool pool)
              (setf size-during-close (redis-kit:pool-size pool))))
        (redis-kit:close-pool pool))
      (expect size-during-close :to-be 1)
      (expect (redis-kit:pool-size pool) :to-be 0))))
