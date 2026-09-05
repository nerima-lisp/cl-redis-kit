; paredit:ignore-file leftover-inspect-call -- CL-WEAVE's DESCRIBE is the BDD test DSL, not a debugger inspection call.
(in-package #:redis-kit/test)

(describe
    "generated command metadata"
  (it "keeps command declarations inspectable"
    (expect-assertions 6)
    (let* ((spec (redis-kit:redis-command-specification 'redis-kit:get))
           (names (redis-kit:redis-command-specification-names)))
      (expect (redis-kit:redis-command-spec-p spec) :to-be-truthy)
      (expect (redis-kit:redis-command-spec-command spec) :to-equal "GET")
      (expect (redis-kit:redis-command-spec-lambda-list spec)
              :to-satisfy
              (lambda (lambda-list)
                (equal lambda-list
                       '(redis-kit::key &key
                         (redis-kit::decode :utf-8)
                         redis-kit::timeout
                         (redis-kit::retry-safe-p t)))))
      (expect (redis-kit:redis-command-spec-decode spec)
              :to-satisfy
              (lambda (decode-form)
                (eq decode-form 'redis-kit::decode)))
      (expect (member 'redis-kit:get names) :to-be-truthy)
      (expect names
              :to-equal
              (sort (copy-list names) #'string< :key #'symbol-name)))))

  (it "rejects declarations with missing wire arguments"
    (signals error
      (macroexpand-1
       '(redis-kit:define-redis-command
            redis-kit::invalid-test-only-command
            "INVALID"
            (key)))))
