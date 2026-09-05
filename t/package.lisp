; paredit:ignore-file leftover-inspect-call -- CL-WEAVE's DESCRIBE is the BDD test DSL, not a debugger inspection call.
(defpackage #:redis-kit/test
  (:use #:cl)
  (:shadowing-import-from #:cl-weave #:describe)
  (:import-from #:cl-weave
                #:it
                #:it-fuzz
                #:it-property
                #:expect
                #:signals
                #:expect-assertions
                #:with-mocked-functions
                #:run-all
                #:gen-integer
                #:gen-list
                #:gen-string
                #:gen-tuple)
  (:export #:run-tests))

(in-package #:redis-kit/test)

(defun test-octets (&rest bytes)
  (make-array (length bytes)
              :element-type '(unsigned-byte 8)
              :initial-contents bytes))

(defun decode-test-reply (octets &key (start 0) end)
  (multiple-value-bind (reply next)
      (redis-kit:decode-reply octets :start start :end end)
    (unless (= next (or end (length octets)))
      (error "Test frame did not consume its expected input."))
    reply))

(defun test-error-reply (message)
  (let ((payload (cl-codec-kit:string-to-octets message :encoding :utf-8)))
    (decode-test-reply
     (concatenate '(vector (unsigned-byte 8))
                  (test-octets 45)
                  payload
                  (test-octets 13 10)))))

(defun selected-test-count ()
  (let* ((plan (cl-weave:collect-test-plan (cl-weave:root-suite)))
         (facts (cl-weave:test-plan-facts plan)))
    (length (cl-weave:test-plan-where facts
                                      (:status ?test :run)))))

(defun run-tests (&key (reporter :spec)
                       coverage
                       coverage-output
                       coverage-report-directory
                       coverage-include-pathnames
                       coverage-exclude-pathnames
                       coverage-minimum-expression
                       coverage-minimum-branch
                       (coverage-reset t))
  (let ((selected-tests (selected-test-count)))
    (unless (plusp selected-tests)
      (error "cl-redis-kit test suite selected no tests."))
    (format t "~&cl-redis-kit/test: selected ~D tests~%" selected-tests)
    (unless (cl-weave:run-all
              :reporter reporter
              :timeout-ms 20000
              :max-workers 1
              :pass-with-no-tests nil
              :coverage coverage
              :coverage-output coverage-output
              :coverage-report-directory coverage-report-directory
              :coverage-include-pathnames coverage-include-pathnames
              :coverage-exclude-pathnames coverage-exclude-pathnames
              :coverage-minimum-expression coverage-minimum-expression
              :coverage-minimum-branch coverage-minimum-branch
              :coverage-reset coverage-reset)
      (error "cl-redis-kit test suite failed"))
    (format t "~&cl-redis-kit/test: ~D selected tests passed~%" selected-tests))
  t)

(describe
    "public data contracts"
  (it "exposes condition payloads"
    (let ((protocol
            (make-condition 'redis-kit:redis-protocol-error
                            :message "malformed"
                            :cause :input
                            :position 7))
          (server
            (make-condition 'redis-kit:redis-server-error
                            :message "wrong type"
                            :cause :command
                            :code "WRONGTYPE"
                            :reply :reply)))
      (expect (redis-kit:redis-error-cause protocol) :to-be :input)
      (expect (redis-kit:redis-error-position protocol) :to-be 7)
      (expect (redis-kit:redis-error-cause server) :to-be :command)
      (expect (redis-kit:redis-error-code server) :to-equal "WRONGTYPE")
      (expect (redis-kit:redis-error-reply server) :to-be :reply)))

  (it "exposes connection configuration"
    (let ((connection
            (redis-kit:make-connection
             :host "redis.example"
             :port 6380
             :protocol :resp2
             :timeout 3
             :tls '(:verify t)
             :retry-policy :policy
             :handshake nil)))
      (unwind-protect
           (progn
             (expect (redis-kit:redis-connection-p connection) :to-be-truthy)
             (expect (redis-kit:redis-connection-p :not-a-connection)
                     :to-be
                     nil)
             (expect (redis-kit:connection-host connection)
                     :to-equal
                     "redis.example")
             (expect (redis-kit:connection-port connection) :to-be 6380)
             (expect (redis-kit:connection-protocol connection) :to-be :resp2)
             (expect (redis-kit:connection-timeout connection) :to-be 3)
             (expect (redis-kit:connection-tls connection)
                     :to-equal
                     '(:verify t))
             (expect (redis-kit:connection-retry-policy connection)
                     :to-be
                     :policy))
        (redis-kit:close-connection connection))))

  (it "exposes metrics and command metadata"
    (let ((metrics (redis-kit:make-redis-metrics))
          (spec (redis-kit:redis-command-specification 'redis-kit:get)))
      (expect (redis-kit:redis-metrics-p metrics) :to-be-truthy)
      (expect (redis-kit:redis-metrics-p :not-metrics) :to-be nil)
      (expect (redis-kit:redis-metrics-registry metrics) :to-be-truthy)
      (expect (redis-kit:redis-command-spec-name spec) :to-be 'redis-kit:get)
      (expect (redis-kit:redis-command-spec-arguments spec) :to-be-truthy)
      (expect (redis-kit:redis-command-spec-timeout spec) :to-be-truthy)
      (expect (redis-kit:redis-command-spec-retry-safe-p spec)
              :to-be-truthy)))

  (it "exposes pool configuration"
    (let ((pool (redis-kit:make-pool :max-size 3 :max-wait 1)))
      (unwind-protect
           (progn
             (expect (redis-kit:redis-pool-p pool) :to-be-truthy)
             (expect (redis-kit:redis-pool-p :not-a-pool) :to-be nil)
             (expect (redis-kit:pool-max-size pool) :to-be 3)
             (expect (redis-kit:pool-max-wait pool) :to-be 1))
        (redis-kit:close-pool pool)))))
