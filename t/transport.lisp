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

(describe
    "socket transport boundary"
  (it "normalizes a nanosecond rounding carry"
    (let ((duration
            (redis-kit::%timeout-duration (/ 19999999995 10000000000))))
      (expect (cl-date-kit:duration-seconds duration) :to-be 2)
      (expect (cl-date-kit:duration-nanos duration) :to-be 0)))

  (it "clears transport handles when close operations fail"
    (let ((connection (redis-kit:make-connection :handshake nil))
          (stream (gensym "STREAM-"))
          (socket (gensym "SOCKET-")))
      (setf (redis-kit::%connection-stream connection) stream
            (redis-kit::%connection-socket connection) socket)
      ;; These values intentionally are not streams/sockets.  The cleanup
      ;; handlers must still clear both slots when CLOSE or SOCKET-CLOSE
      ;; signals a type error; locked COMMON-LISP functions are not mocked.
      (redis-kit::%close-transport connection)
      (expect (redis-kit::%connection-stream connection) :to-be nil)
      (expect (redis-kit::%connection-socket connection) :to-be nil)
      (redis-kit:close-connection connection)))

  (it "rejects malformed socket boundary requests"
    (let ((connection (redis-kit:make-connection :handshake nil)))
      (setf (redis-kit::%connection-stream connection)
            (make-string-output-stream))
      (unwind-protect
           (signals redis-kit:redis-connection-error
             (redis-kit::%socket-boundary-request
              connection
              (list :bytes nil :replies 1)
              nil))
        (redis-kit:close-connection connection))))

  (it "routes default connections through the socket network boundary"
    (let ((connection (redis-kit:make-connection :handshake nil)))
      (setf (redis-kit::%connection-stream connection)
            (make-string-output-stream))
      (unwind-protect
           (signals redis-kit:redis-connection-error
             (cl-boundary-kit:network-boundary-request
              (redis-kit:connection-network-boundary connection)
              (list :bytes nil :replies 1)
              :timeout nil))
        (redis-kit:close-connection connection))))

  (it "establishes plain and TLS socket transports through public boundaries"
    (let ((plain (redis-kit:make-connection :handshake nil))
          (secure (redis-kit:make-connection
                   :handshake nil
                   :tls '(:verify :required)))
          (connected 0)
          (upgraded nil))
      (unwind-protect
           (progn
             (with-mocked-functions
                 (((symbol-function 'usocket:socket-connect)
                    (lambda (host port &rest options)
                      (declare (ignore host port options))
                      (incf connected)
                      (list :socket connected)))
                  ((symbol-function 'usocket:socket-stream)
                    (lambda (socket)
                      (declare (ignore socket))
                      :plain-stream))
                  ((symbol-function 'redis-kit::%upgrade-tls-stream)
                    (lambda (stream host options)
                      (declare (ignore stream host options))
                      (setf upgraded t)
                      :tls-stream)))
               (redis-kit::%establish-transport plain)
               (redis-kit::%establish-transport secure))
             (expect connected :to-be 2)
             (expect (redis-kit::%connection-stream plain)
                     :to-be :plain-stream)
             (expect (redis-kit::%connection-stream secure)
                     :to-be :tls-stream)
             (expect upgraded :to-be t)
             (expect (redis-kit::%connection-socket plain) :to-be-truthy)
             (expect (redis-kit::%connection-socket secure) :to-be-truthy))
        (redis-kit:close-connection plain)
        (redis-kit:close-connection secure))))

  (it "invalidates connections for boundary connection errors"
    (let ((connection
            (redis-kit:make-connection
             :handshake nil
             :network-boundary
             (cl-boundary-kit:make-network-boundary
              :request-fn
              (lambda (request &key timeout)
                (declare (ignore request timeout))
                (error 'redis-kit:redis-connection-error
                       :message "synthetic connection failure"))))))
      (setf (redis-kit:connection-state connection) :ready)
      (unwind-protect
           (progn
             (signals redis-kit:redis-connection-error
               (redis-kit::%request-replies
                connection (test-octets 43 79 75 13 10) 1 nil))
             (expect (redis-kit:connection-state connection)
                     :to-be :broken))
        (redis-kit:close-connection connection)))
    (let ((connection
            (redis-kit:make-connection
             :handshake nil
             :network-boundary
             (cl-boundary-kit:make-network-boundary
              :request-fn
              (lambda (request &key timeout)
                (declare (ignore request timeout))
                (error 'redis-kit:redis-server-error
                       :message "WRONGTYPE synthetic server failure"
                       :code "WRONGTYPE"))))))
      (setf (redis-kit:connection-state connection) :ready)
      (unwind-protect
           (progn
             (signals redis-kit:redis-server-error
               (redis-kit::%request-replies
                connection (test-octets 43 79 75 13 10) 1 nil))
             (expect (redis-kit:connection-state connection)
                     :to-be :ready))
        (redis-kit:close-connection connection))))

  (it "routes push replies and preserves pipeline order at the socket boundary"
    (let* ((connection (redis-kit:make-connection
                        :handshake nil
                        :max-pushes 1))
           (push-one (redis-kit::make-redis-reply :push (list :one)))
           (push-two (redis-kit::make-redis-reply :push (list :two)))
           (reply (test-simple-reply "OK"))
           (replies (list push-one push-two reply)))
      (setf (redis-kit::%connection-stream connection)
            (make-string-output-stream))
      (unwind-protect
           (progn
             (with-mocked-functions
                 (((symbol-function 'redis-kit:read-reply)
                    (lambda (&rest arguments)
                      (declare (ignore arguments))
                      (pop replies))))
               (expect
                (redis-kit::%socket-boundary-request
                 connection
                 (list :bytes (test-octets) :replies 1)
                 nil)
                :to-be reply))
             (expect (first (redis-kit::%connection-pushes connection))
                     :to-be push-two)
             (expect (length (redis-kit::%connection-pushes connection))
                     :to-be 1))
        (redis-kit:close-connection connection)))
    (let* ((connection (redis-kit:make-connection :handshake nil))
           (first-reply (test-simple-reply "ONE"))
           (second-reply (test-simple-reply "TWO"))
           (replies (list first-reply second-reply)))
      (setf (redis-kit::%connection-stream connection)
            (make-string-output-stream))
      (unwind-protect
           (with-mocked-functions
               (((symbol-function 'redis-kit:read-reply)
                  (lambda (&rest arguments)
                    (declare (ignore arguments))
                    (pop replies))))
             (expect
              (redis-kit::%socket-boundary-request
               connection
               (list :bytes (test-octets) :replies 2)
               nil)
              :to-equal
              (list first-reply second-reply)))
        (redis-kit:close-connection connection)))
    (let* ((handled nil)
           (connection
             (redis-kit:make-connection
              :handshake nil
              :push-handler (lambda (reply) (push reply handled))))
           (push-reply (redis-kit::make-redis-reply :push (list :handled)))
           (reply (test-simple-reply "OK"))
           (replies (list push-reply reply)))
      (setf (redis-kit::%connection-stream connection)
            (make-string-output-stream))
      (unwind-protect
           (progn
             (with-mocked-functions
                 (((symbol-function 'redis-kit:read-reply)
                    (lambda (&rest arguments)
                      (declare (ignore arguments))
                      (pop replies))))
               (expect
                (redis-kit::%socket-boundary-request
                 connection
                 (list :bytes (test-octets) :replies 1)
                 nil)
                :to-be reply))
             (expect (first handled) :to-be push-reply)
             (expect (redis-kit::%connection-pushes connection) :to-be nil))
        (redis-kit:close-connection connection))))

  (it "converts socket I/O failures to connection errors"
    (let ((connection (redis-kit:make-connection :handshake nil)))
      (setf (redis-kit::%connection-stream connection)
            (make-string-output-stream))
      (unwind-protect
           (progn
             (with-mocked-functions
                 (((symbol-function 'redis-kit:read-reply)
                    (lambda (&rest arguments)
                      (declare (ignore arguments))
                      (error 'redis-kit:redis-server-error
                             :message "ERR socket reply" :code "ERR"))))
               (signals redis-kit:redis-server-error
                 (redis-kit::%socket-boundary-request
                 connection
                  (list :bytes (test-octets) :replies 1)
                  nil)))
             (expect (redis-kit:connection-state connection)
                     :to-be :broken))
        (redis-kit:close-connection connection)))
    (let ((connection (redis-kit:make-connection :handshake nil)))
      (setf (redis-kit::%connection-stream connection)
            (make-string-output-stream))
      (unwind-protect
           (progn
             (with-mocked-functions
                 (((symbol-function 'redis-kit:read-reply)
                    (lambda (&rest arguments)
                      (declare (ignore arguments))
                      (error "synthetic socket reader failure"))))
               (signals redis-kit:redis-connection-error
                 (redis-kit::%socket-boundary-request
                 connection
                  (list :bytes (test-octets) :replies 1)
                  nil)))
             (expect (redis-kit:connection-state connection)
                     :to-be :broken))
        (redis-kit:close-connection connection)))))
