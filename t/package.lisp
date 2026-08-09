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

(defun run-tests (&key (reporter :spec)
                       coverage
                       coverage-output
                       coverage-report-directory
                       coverage-include-pathnames
                       coverage-exclude-pathnames
                       coverage-minimum-expression
                       coverage-minimum-branch)
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
            :coverage-minimum-branch coverage-minimum-branch)
    (error "cl-redis-kit test suite failed"))
  (format t "~&cl-redis-kit/test: successful completion with 0 failures~%")
  t)
