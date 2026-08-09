(defpackage #:redis-kit/resilience-test
  (:use #:cl)
  (:import-from #:cl-weave
                #:it
                #:expect
                #:with-mocked-functions
                #:run-all)
  (:export #:run-tests))

(in-package #:redis-kit/resilience-test)

(defun test-octets (&rest octets)
  (coerce octets '(vector (unsigned-byte 8))))

(defun simple-reply (text)
  (multiple-value-bind (reply next)
      (redis-kit:decode-reply
       (concatenate '(vector (unsigned-byte 8))
                    (test-octets 43)
                    (cl-codec-kit:string-to-octets text :encoding :utf-8)
                    (test-octets 13 10)))
    (declare (ignore next))
    reply))

(defun make-test-boundary ()
  (cl-boundary-kit:make-network-boundary
   :request-fn (lambda (request &key timeout)
                 (declare (ignore request timeout))
                 (simple-reply "PONG"))))

(it "delegates retry-safe commands to cl-resilience-kit"
  (let ((calls nil)
        (connection
          (redis-kit:make-connection
           :network-boundary (make-test-boundary)
           :handshake nil
           :retry-policy :test-policy)))
    (unwind-protect
         (with-mocked-functions
             (((symbol-function 'cl-resilience-kit:call-with-resilience)
                (lambda (thunk &key retry-policy operation &allow-other-keys)
                  (push (list retry-policy operation) calls)
                  (funcall thunk))))
           (expect (redis-kit:ping connection :retry-safe-p t)
                   :to-equal
                   "PONG")
           (expect calls
                   :to-equal
                   '((:test-policy "PING"))))
      (redis-kit:close-connection connection))))

(defun run-tests ()
  (unless (cl-weave:run-all
            :reporter :spec
            :timeout-ms 20000
            :max-workers 1
            :pass-with-no-tests nil)
    (error "cl-redis-kit resilience tests failed"))
  t)
