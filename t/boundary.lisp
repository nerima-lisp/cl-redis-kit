; paredit:ignore-file declarative-style-score -- This integration fixture intentionally exercises several boundary behaviors in one readable scenario file.
; paredit:ignore-file leftover-inspect-call -- CL-WEAVE's DESCRIBE is the BDD test DSL, not a debugger inspection call.
(in-package #:redis-kit/test)

(defun test-simple-reply (text)
  (let ((payload (cl-codec-kit:string-to-octets text :encoding :utf-8)))
    (decode-test-reply
     (concatenate '(vector (unsigned-byte 8))
                  (test-octets 43)
                  payload
                  (test-octets 13 10)))))

(defun test-bulk-reply (text)
  (let ((payload (cl-codec-kit:string-to-octets text :encoding :utf-8)))
    (decode-test-reply
     (concatenate '(vector (unsigned-byte 8))
                  (test-octets 36 55 13 10)
                  payload
                  (test-octets 13 10)))))

(defun test-command-value (request)
  (multiple-value-bind (reply next)
      (redis-kit:decode-reply (getf request :bytes))
    (declare (ignore next))
    (redis-kit:reply-value reply)))

(defun make-test-boundary ()
  (cl-boundary-kit:make-recording-network-boundary
   :delegate
   (cl-boundary-kit:make-network-boundary
    :request-fn
    (lambda (request &key timeout)
      (declare (ignore timeout))
      (let ((count (getf request :replies)))
        (multiple-value-bind (command-reply next)
            (redis-kit:decode-reply (getf request :bytes))
          (declare (ignore next))
          (let ((command (first (redis-kit:reply-value command-reply))))
            (if (> count 1)
                (loop repeat count collect (test-simple-reply "OK"))
                (cond
                  ((string= command "PING") (test-simple-reply "PONG"))
                  ((string= command "GET") (test-bulk-reply "fixture"))
                  (t (test-simple-reply "OK")))))))))))

(describe
    "network boundary"
  (it "accepts queued replies from the package test boundary"
    (let* ((boundary
             (cl-boundary-kit:make-test-network-boundary
              :responses (list (test-simple-reply "QUEUED"))))
           (connection (redis-kit:make-connection
                        :protocol :resp2
                        :handshake nil
                        :network-boundary boundary)))
      (unwind-protect
           (expect (redis-kit:execute connection "PING") :to-equal "QUEUED")
        (redis-kit:close-connection connection))))

  (it "uses injectable and recording boundaries"
    (let* ((boundary (make-test-boundary))
           (connection (redis-kit:make-connection
                        :protocol :resp2
                        :handshake nil
                        :network-boundary boundary)))
      (unwind-protect
           (progn
             (expect (redis-kit:ping connection :timeout 1) :to-equal "PONG")
             (expect (redis-kit:set connection "k" "v") :to-equal "OK")
             (expect (redis-kit:get connection "k") :to-equal "fixture")
             (expect (length (redis-kit:pipeline
                               connection
                               (list (list "PING") (list "PING"))))
                     :to-be 2)
             (expect (length (cl-boundary-kit:recording-network-calls boundary))
                     :to-be 4))
        (redis-kit:close-connection connection)))))

  (it "passes the inherited operation timeout to the network boundary"
    (let ((observed-timeout nil)
          (connection
            (redis-kit:make-connection
             :timeout 7
             :protocol :resp2
             :handshake nil
             :network-boundary
             (cl-boundary-kit:make-network-boundary
              :request-fn
              (lambda (request &key timeout)
                (declare (ignore request))
                (setf observed-timeout timeout)
                (test-simple-reply "PONG"))))))
      (unwind-protect
           (progn
             (expect (redis-kit:ping connection) :to-equal "PONG")
             (expect observed-timeout :to-be 7))
        (redis-kit:close-connection connection))))

(describe
    "command argument encoding"
  (it "preserves SET expiration options and timeout separation"
    (let ((commands nil)
          (connection nil))
      (setf connection
            (redis-kit:make-connection
             :protocol :resp2
             :handshake nil
             :network-boundary
             (cl-boundary-kit:make-network-boundary
              :request-fn
              (lambda (request &key timeout)
                (declare (ignore timeout))
                (multiple-value-bind (reply next)
                    (redis-kit:decode-reply (getf request :bytes))
                  (declare (ignore next))
                  (push (redis-kit:reply-value reply) commands)
                  (test-simple-reply "OK"))))))
      (unwind-protect
           (progn
             (expect (redis-kit:set connection "k" "v"
                                     :ex 1
                                     :timeout 1)
                     :to-equal "OK")
             (expect (first commands)
                     :to-equal
                     (list "SET" "k" "v" "EX" "1")))
        (redis-kit:close-connection connection)))))

(describe
    "connection lifecycle"
  (it "falls back from HELLO and completes authentication and database selection"
    (let ((commands nil)
          (connection nil))
      (setf connection
            (redis-kit:make-connection
             :protocol :resp3
             :username "user"
             :password "secret"
             :database 4
             :network-boundary
             (cl-boundary-kit:make-network-boundary
              :request-fn
              (lambda (request &key timeout)
                (declare (ignore timeout))
                (let ((command (test-command-value request)))
                  (push command commands)
                  (cond
                    ((string= (first command) "HELLO")
                     (test-error-reply "ERR unknown command 'HELLO'"))
                    ((string= (first command) "PING")
                     (test-simple-reply "PONG"))
                    (t
                     (test-simple-reply "OK"))))))))
      (unwind-protect
           (progn
             (expect (redis-kit:ping connection) :to-equal "PONG")
             (expect (redis-kit:connection-protocol connection) :to-be :resp2)
             (expect (nreverse commands)
                     :to-equal
                     (list (list "HELLO" "3")
                           (list "AUTH" "user" "secret")
                           (list "SELECT" "4")
                           (list "PING"))))
        (redis-kit:close-connection connection))))

  (it "wraps boundary failures and invalidates the connection"
    (let ((connection
            (redis-kit:make-connection
             :protocol :resp2
             :handshake nil
             :network-boundary
             (cl-boundary-kit:make-network-boundary
              :request-fn
              (lambda (request &key timeout)
                (declare (ignore request timeout))
                (error "synthetic boundary failure"))))))
      (unwind-protect
           (progn
             (signals redis-kit:redis-connection-error
               (redis-kit:ping connection))
             (expect (redis-kit:connection-state connection) :to-be :broken)
             (expect (redis-kit:connection-open-p connection) :to-be nil))
        (redis-kit:close-connection connection))))

  (it "converts operation timeouts into closed connections"
    (let ((connection
            (redis-kit:make-connection
             :protocol :resp2
             :handshake nil
             :network-boundary
             (cl-boundary-kit:make-network-boundary
              :request-fn
              (lambda (request &key timeout)
                (declare (ignore request timeout))
                (sleep 0.1)
                (test-simple-reply "PONG"))))))
      (unwind-protect
           (progn
             (signals redis-kit:redis-timeout-error
               (redis-kit:ping connection :timeout 0.01))
             (expect (redis-kit:connection-state connection) :to-be :broken))
        (redis-kit:close-connection connection))))

  (it "rejects invalid connection and TLS options before opening"
    (signals redis-kit:redis-client-error
      (redis-kit:make-connection :host ""))
    (signals redis-kit:redis-client-error
      (redis-kit:make-connection :host :not-a-string))
    (signals redis-kit:redis-client-error
      (redis-kit:make-connection :port -1))
    (signals redis-kit:redis-client-error
      (redis-kit:make-connection :port :not-an-integer))
    (signals redis-kit:redis-client-error
      (redis-kit:make-connection :protocol :resp4))
    (signals redis-kit:redis-client-error
      (redis-kit:make-connection :timeout -1))
    (signals redis-kit:redis-client-error
      (redis-kit:make-connection :timeout :not-a-number))
    (signals redis-kit:redis-client-error
      (redis-kit:make-connection :database -1))
    (signals redis-kit:redis-client-error
      (redis-kit:make-connection :database :not-an-integer))
    (signals redis-kit:redis-client-error
      (redis-kit:make-connection :max-pushes -1))
    (signals redis-kit:redis-client-error
      (redis-kit:make-connection :max-pushes :not-an-integer))
    (signals redis-kit:redis-client-error
      (redis-kit:make-connection :tls '(:verify)))
    (signals redis-kit:redis-client-error
      (redis-kit:make-connection :tls '(:unknown t))))

  (it "preserves explicitly supplied zero connection timeouts"
    (let ((connection
            (redis-kit:make-connection
             :connect-timeout 0
             :read-timeout 0)))
      (unwind-protect
           (progn
             (expect (redis-kit::%connection-connect-timeout connection) :to-be 0)
             (expect (redis-kit::%connection-read-timeout connection) :to-be 0))
        (redis-kit:close-connection connection))))

  (it "rejects retry-safe execution without the optional resilience system"
    (let ((connection
            (redis-kit:make-connection
             :network-boundary (make-test-boundary)
             :handshake nil
             :retry-policy :test-policy)))
      (unwind-protect
           (signals redis-kit:redis-client-error
             (redis-kit:ping connection :retry-safe-p t))
        (redis-kit:close-connection connection))))

  (it "rejects invalid command timeouts before opening"
    (let ((connection
            (redis-kit:make-connection
             :protocol :resp2
             :handshake nil
             :network-boundary (make-test-boundary))))
      (unwind-protect
           (progn
             (signals redis-kit:redis-client-error
               (redis-kit:ping connection :timeout -1))
             (signals redis-kit:redis-client-error
               (redis-kit:ping connection :timeout :not-a-number)))
        (redis-kit:close-connection connection))))

  (it "rejects malformed pipeline commands before network I/O"
    (signals redis-kit:redis-client-error
      (redis-kit:pipeline nil (list nil)))
    (signals redis-kit:redis-client-error
      (redis-kit:pipeline nil (list (cons "PING" "extra"))))))
