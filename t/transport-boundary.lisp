; paredit:ignore-file leftover-inspect-call -- CL-WEAVE's DESCRIBE is the BDD test DSL, not a debugger inspection call.
(in-package #:redis-kit/test)

(describe
    "boundary result normalization"
  (it "accepts scalar and pipeline boundary results"
    (let ((first-reply (test-simple-reply "OK"))
          (second-reply (test-simple-reply "PONG")))
      (expect
       (redis-kit::%normalize-boundary-result first-reply 1)
       :to-be first-reply)
      (expect
       (redis-kit::%normalize-boundary-result (list first-reply) 1)
       :to-be first-reply)
      (expect
       (redis-kit::%normalize-boundary-result
        (list first-reply second-reply)
        2)
       :to-equal
       (list first-reply second-reply))
      (signals redis-kit:redis-connection-error
        (redis-kit::%normalize-boundary-result nil 1))
      (signals redis-kit:redis-connection-error
        (redis-kit::%normalize-boundary-result (list first-reply) 2)))))
