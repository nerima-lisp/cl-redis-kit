; paredit:ignore-file leftover-inspect-call -- CL-WEAVE's DESCRIBE is the BDD test DSL, not a debugger inspection call.
(in-package #:redis-kit/test)

(defun make-cps-test-connection ()
  (redis-kit:make-connection
   :protocol :resp2
   :handshake nil
   :network-boundary (make-test-boundary)))

(describe
    "continuation resource boundaries"
  (it "opens and closes around a successful continuation"
    (let ((connection (make-cps-test-connection)))
      (unwind-protect
           (progn
             (expect
              (redis-kit:call-with-connection
               connection
               (lambda (active)
                 (expect (redis-kit:connection-open-p active) :to-be t)
                 (redis-kit:ping active)))
              :to-equal "PONG")
             (expect (redis-kit:connection-state connection) :to-be :closed))
        (redis-kit:close-connection connection))))

  (it "closes when the continuation signals"
    (let ((connection (make-cps-test-connection)))
      (unwind-protect
           (progn
             (signals error
               (redis-kit:call-with-connection
                connection
                (lambda (active)
                  (expect (redis-kit:connection-open-p active) :to-be t)
                  (error "synthetic continuation failure"))))
             (expect (redis-kit:connection-state connection) :to-be :closed))
        (redis-kit:close-connection connection))))

  (it "uses the macro declaration for scoped use"
    (expect
     (redis-kit:with-connection
         (connection
          :protocol :resp2
          :handshake nil
          :network-boundary (make-test-boundary))
       (redis-kit:ping connection))
     :to-equal "PONG"))

  (it "validates the CPS boundary"
    (signals redis-kit:redis-client-error
      (redis-kit:call-with-connection nil #'identity))
    (let ((connection (make-cps-test-connection)))
      (unwind-protect
           (signals redis-kit:redis-client-error
             (redis-kit:call-with-connection connection nil))
        (redis-kit:close-connection connection)))))

  (it "rejects empty pipelines before opening a connection"
    (signals redis-kit:redis-client-error
      (redis-kit:pipeline nil nil))
    (signals redis-kit:redis-client-error
      (redis-kit:pipeline nil :not-a-command-list))
    (signals redis-kit:redis-client-error
      (redis-kit:pipeline nil (list :not-a-command))))

(describe
    "generic command execution"
  (it "separates typed replies and decoded values"
    (let ((connection (make-cps-test-connection)))
      (unwind-protect
           (progn
             (expect
              (redis-kit:redis-reply-type
               (redis-kit:execute-reply connection "PING"
                                        :timeout 1
                                        :retry-safe-p nil))
              :to-be :simple-string)
             (expect (redis-kit:execute connection "GET" "key" :decode nil)
                     :to-equalp
                     (test-octets 102 105 120 116 117 114 101)))
        (redis-kit:close-connection connection))))

  (it "rejects missing option values before I/O"
    (let ((connection (make-cps-test-connection)))
      (unwind-protect
           (progn
             (signals redis-kit:redis-client-error
               (redis-kit:execute-reply connection "PING" :timeout))
             (signals redis-kit:redis-client-error
               (redis-kit:execute-reply connection "PING" :retry-safe-p)))
        (redis-kit:close-connection connection)))))

(describe
    "push reply queue"
  (it "drains queued pushes in arrival order"
    (let ((connection (make-cps-test-connection))
          (first-reply
            (decode-test-reply
             (test-octets 62 49 13 10 43 97 13 10)))
          (second-reply
            (decode-test-reply
             (test-octets 62 49 13 10 43 98 13 10))))
      (unwind-protect
           (progn
             (setf (redis-kit::%connection-pushes connection)
                   (list second-reply first-reply))
             (expect (redis-kit:drain-pushes connection)
                     :to-equal
                     (list first-reply second-reply))
              (expect (redis-kit:drain-pushes connection) :to-be nil))
        (redis-kit:close-connection connection)))))

  (it "rejects non-connections at the push queue boundary"
    (signals redis-kit:redis-client-error
      (redis-kit:drain-pushes nil)))
