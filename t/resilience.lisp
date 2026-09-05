(defpackage #:redis-kit/resilience-test
  (:use #:cl)
  (:import-from #:cl-weave
                #:it
                #:expect
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

(it "retries retry-safe commands through cl-resilience-kit"
  (let* ((attempts 0)
         (policy (cl-resilience-kit:make-retry-policy
                  :max-attempts 2
                  :retry-safe-p t
                  :condition-classifier
                  (lambda (condition attempt)
                    (declare (ignore condition attempt))
                    t)))
         (connection
           (redis-kit:make-connection
            :network-boundary
            (cl-boundary-kit:make-network-boundary
             :request-fn (lambda (request &key timeout)
                           (declare (ignore request timeout))
                           (incf attempts)
                           (if (= attempts 1)
                               (error "transient test failure")
                               (simple-reply "PONG"))))
            :handshake nil
            :retry-policy policy)))
    (unwind-protect
         (progn
           (expect (redis-kit:ping connection :retry-safe-p t)
                   :to-equal
                   "PONG")
           (expect attempts :to-be 2))
      (redis-kit:close-connection connection))))

(defun selected-test-count ()
  (length
   (cl-weave:collect-test-plan
    :packages (list (find-package '#:redis-kit/resilience-test)))))

(defun run-tests ()
  (unless (plusp (selected-test-count))
    (error "cl-redis-kit resilience test plan is empty"))
  (unless (cl-weave:run-all
            :reporter :spec
            :timeout-ms 20000
            :max-workers 1
            :pass-with-no-tests nil)
    (error "cl-redis-kit resilience tests failed"))
  t)
