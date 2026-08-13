; paredit:ignore-file leftover-inspect-call -- CL-WEAVE's DESCRIBE is the BDD test DSL, not a debugger inspection call.
(in-package #:redis-kit/test)

(describe
    "Redis conditions"
  (it "reports messages with and without causes"
    (let ((without-cause (make-condition 'redis-kit:redis-error
                                         :message "plain"))
          (with-cause (make-condition 'redis-kit:redis-error
                                      :message "wrapped"
                                      :cause :cause)))
      (expect (redis-kit:redis-error-message without-cause)
              :to-equal
              "plain")
      (expect (redis-kit:redis-error-cause without-cause) :to-be nil)
      (expect (with-output-to-string (stream)
                (princ without-cause stream))
              :to-equal
              "plain")
      (expect (with-output-to-string (stream)
                (princ with-cause stream))
              :to-equal
              "wrapped (CAUSE)")))

  (it "retains protocol and server metadata"
    (let ((protocol (make-condition 'redis-kit:redis-protocol-error
                                   :message "bad frame"
                                   :position 7))
          (server (make-condition 'redis-kit:redis-server-error
                                  :message "ERR"
                                  :code "ERR"
                                  :reply :reply)))
      (expect (redis-kit:redis-error-position protocol) :to-equal 7)
      (expect (redis-kit:redis-error-code server) :to-equal "ERR")
      (expect (redis-kit:redis-error-reply server) :to-be :reply)))

  (it "provides defaults for optional condition metadata"
    (let ((protocol (make-condition 'redis-kit:redis-protocol-error
                                   :message "bad frame"))
          (server (make-condition 'redis-kit:redis-server-error
                                  :message "ERR")))
      (expect (redis-kit:redis-error-position protocol) :to-be nil)
      (expect (redis-kit:redis-error-code server) :to-be nil)
      (expect (redis-kit:redis-error-reply server) :to-be nil))))

(describe
    "transport helpers"
  (it "converts seconds to date-kit durations"
    (expect (redis-kit::%timeout-duration nil) :to-be nil)
    (let ((duration (redis-kit::%timeout-duration 1.25)))
      (expect (cl-date-kit:duration-seconds duration) :to-be 1)
      (expect (cl-date-kit:duration-nanos duration) :to-be 250000000)))

  (it "parses server error codes and unsupported hello errors"
    (expect (redis-kit::%server-error-code "ERR") :to-equal "ERR")
    (expect (redis-kit::%server-error-code "ERR wrong type") :to-equal "ERR")
    (let ((unsupported
            (make-condition 'redis-kit:redis-server-error
                            :message "ERR unknown command 'HELLO'"
                            :code "ERR"))
          (other
            (make-condition 'redis-kit:redis-server-error
                            :message "ERR wrong type"
                            :code "ERR"))
          (other-code
            (make-condition 'redis-kit:redis-server-error
                            :message "ERR unknown command 'HELLO'"
                            :code "NOAUTH")))
      (expect (redis-kit::%unsupported-hello-error-p unsupported)
              :to-be t)
      (expect (redis-kit::%unsupported-hello-error-p other)
              :to-be nil)
      (expect (redis-kit::%unsupported-hello-error-p other-code)
              :to-be nil)))

  (it "renders both textual and non-textual error replies"
    (expect (redis-kit::%reply-error-text (test-error-reply "ERR nope"))
            :to-equal
            "ERR nope")
    (expect
     (redis-kit::%reply-error-text
      (redis-kit::make-redis-reply :error 42))
     :to-equal
     "42"))

  (it "raises structured server errors"
    (let ((reply (test-error-reply "WRONGTYPE value"))
          (condition nil))
      (handler-case
          (redis-kit::%check-server-reply reply)
        (redis-kit:redis-server-error (caught)
          (setf condition caught)))
      (expect condition :to-be-truthy)
      (expect (redis-kit:redis-error-code condition) :to-equal "WRONGTYPE")
      (expect (redis-kit:redis-error-message condition)
              :to-equal
              "WRONGTYPE value")))

  (it "rejects requests made before opening"
    (let ((connection
            (redis-kit:make-connection
             :protocol :resp2
             :handshake nil
             :network-boundary (make-test-boundary))))
      (unwind-protect
           (signals redis-kit:redis-connection-error
             (redis-kit::%request-replies
              connection
              (test-octets 43 79 75 13 10)
              1
              nil))
        (redis-kit:close-connection connection))))

  (it "supports an explicitly unbounded operation timeout"
    (let ((connection
            (redis-kit:make-connection
             :timeout nil
             :protocol :resp2
             :handshake nil
             :network-boundary (make-test-boundary))))
      (unwind-protect
           (expect (redis-kit::%call-with-timeout
                    connection nil (lambda () :ok))
                   :to-be :ok)
        (redis-kit:close-connection connection)))))
