; paredit:ignore-file leftover-inspect-call -- CL-WEAVE's DESCRIBE is the BDD test DSL, not a debugger inspection call.
(in-package #:redis-kit/test)

(describe
    "connection lifecycle edges"
  (it "applies documented connection defaults"
    (let ((connection
            (redis-kit:make-connection
             :network-boundary (make-test-boundary))))
      (unwind-protect
           (progn
             (expect (redis-kit:connection-host connection)
                     :to-equal
                     "127.0.0.1")
             (expect (redis-kit:connection-port connection) :to-be 6379)
             (expect (redis-kit:connection-protocol connection) :to-be :resp3)
             (expect (redis-kit:connection-timeout connection) :to-be 5)
             (expect (redis-kit::%connection-connect-timeout connection)
                     :to-be
                     5)
             (expect (redis-kit::%connection-read-timeout connection)
                     :to-be
                     5)
             (expect (redis-kit::%connection-handshake-p connection)
                     :to-be
                     t)
             (expect (redis-kit::%connection-max-pushes connection)
                     :to-be
                     1024))
        (redis-kit:close-connection connection))))

  (it "completes a RESP3 handshake with password-only authentication"
    (let* ((boundary
             (cl-boundary-kit:make-recording-network-boundary
              :delegate
              (cl-boundary-kit:make-network-boundary
               :request-fn
               (lambda (request &key timeout)
                 (declare (ignore timeout))
                 (let ((command (test-command-value request)))
                   (if (string= (first command) "PING")
                       (test-simple-reply "PONG")
                       (test-simple-reply "OK")))))))
           (connection
             (redis-kit:make-connection
              :protocol :resp3
              :password "secret"
              :network-boundary boundary)))
      (unwind-protect
           (progn
             (expect (redis-kit:open-connection connection)
                     :to-be connection)
             (expect (redis-kit:connection-open-p connection) :to-be t)
             (expect (redis-kit:ping connection) :to-equal "PONG")
             (expect (redis-kit:open-connection connection)
                     :to-be connection)
             (expect (mapcar (lambda (call)
                               (test-command-value (getf call :request)))
                             (cl-boundary-kit:recording-network-calls boundary))
                     :to-equal
                     (list (list "HELLO" "3")
                           (list "AUTH" "secret")
                           (list "PING"))))
        (redis-kit:close-connection connection))))

  (it "opens a RESP2 connection without optional handshake steps"
    (let ((connection
            (redis-kit:make-connection
             :protocol :resp2
             :handshake t
             :network-boundary (make-test-boundary))))
      (unwind-protect
           (expect (redis-kit:open-connection connection)
                   :to-be connection)
        (redis-kit:close-connection connection))))

  (it "propagates a non-unsupported HELLO server error"
    (let ((connection
            (redis-kit:make-connection
             :protocol :resp3
             :network-boundary
             (cl-boundary-kit:make-network-boundary
              :request-fn
              (lambda (request &key timeout)
                (declare (ignore request timeout))
                (test-error-reply "ERR wrong type"))))))
      (unwind-protect
           (progn
             (signals redis-kit:redis-server-error
               (redis-kit:open-connection connection))
             (expect (redis-kit:connection-state connection)
                     :to-be :broken))
        (redis-kit:close-connection connection))))

  (it "handles repeated and terminal lifecycle states"
    (let ((connection
            (redis-kit:make-connection
             :protocol :resp2
             :handshake nil
             :network-boundary (make-test-boundary))))
      (unwind-protect
           (progn
             (setf (redis-kit:connection-state connection) :opening)
             (expect (redis-kit:open-connection connection)
                     :to-be connection)
             (setf (redis-kit:connection-state connection) :closed)
             (signals redis-kit:redis-connection-error
               (redis-kit:open-connection connection))
             (expect (redis-kit:connection-open-p nil) :to-be nil)
             (signals redis-kit:redis-client-error
               (redis-kit:open-connection nil))
             (signals redis-kit:redis-client-error
               (redis-kit:close-connection nil)))
        (redis-kit:close-connection connection))))

  (it "invalidates a connection after an unexpected open failure"
    (let ((connection
            (redis-kit:make-connection
             :protocol :resp2
             :handshake nil)))
      (unwind-protect
           (progn
             (with-mocked-functions
                 (((symbol-function 'redis-kit::%establish-transport)
                    (lambda (ignored)
                      (declare (ignore ignored))
                      (error "synthetic open failure"))))
               (signals redis-kit:redis-connection-error
                 (redis-kit:open-connection connection)))
             (expect (redis-kit:connection-state connection)
                     :to-be :broken))
        (redis-kit:close-connection connection))))

  (it "exposes attached and disabled metrics explicitly"
    (let* ((registry (observability-kit:make-metric-registry))
           (with-metrics
             (redis-kit:make-connection
              :protocol :resp2
              :handshake nil
              :metric-registry registry
              :network-boundary (make-test-boundary)))
           (without-metrics
             (redis-kit:make-connection
              :protocol :resp2
              :handshake nil
              :network-boundary (make-test-boundary))))
      (unwind-protect
           (progn
             (expect (redis-kit:connection-metric-registry with-metrics)
                     :to-be registry)
             (expect (not (null (redis-kit:connection-metrics-snapshot
                                  with-metrics)))
                     :to-be t)
             (expect (redis-kit:connection-metric-registry without-metrics)
                     :to-be nil)
             (expect (redis-kit:connection-metrics-snapshot without-metrics)
                     :to-be nil)
             (signals redis-kit:redis-client-error
               (redis-kit:connection-metric-registry nil))
             (signals redis-kit:redis-client-error
               (redis-kit:connection-metrics-snapshot nil)))
        (redis-kit:close-connection with-metrics)
        (redis-kit:close-connection without-metrics))))
  )

(describe
    "TLS boundary"
  (it "reports TLS support as an optional boundary"
    (signals redis-kit:redis-client-error
      (redis-kit::%upgrade-tls-stream
       :plain
       "redis.example"
       '(:verify :optional
         :certificate cert
         :key key
         :password pass))))

  (it "rejects malformed and unknown TLS options"
    (expect (redis-kit::%validate-tls-options nil)
            :to-be
            nil)
    (signals redis-kit:redis-client-error
      (redis-kit::%validate-tls-options :not-a-property-list))
    (let ((options '(:verify t)))
      (expect (redis-kit::%validate-tls-options options)
              :to-equal
              options))
    (signals redis-kit:redis-client-error
      (redis-kit::%validate-tls-options (cons :verify :tail)))
    (signals redis-kit:redis-client-error
      (redis-kit::%validate-tls-options '(:server-name "not-supported")))
    (signals redis-kit:redis-client-error
      (redis-kit::%validate-tls-options '(:verify t "not-a-keyword" t)))))
