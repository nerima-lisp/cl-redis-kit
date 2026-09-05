; paredit:ignore-file leftover-inspect-call -- CL-WEAVE's DESCRIBE is the BDD test DSL, not a debugger inspection call.
(in-package #:redis-kit/test)

(defun codec-edge-parser (octets &key (max-array-length 32) (max-depth 8))
  (redis-kit::%make-resp-parser
   octets 0 32 32 max-array-length max-depth 256 0))

(describe
    "RESP encoder edges"
  (it "encodes symbols and rejects unsupported arguments and commands"
    (expect (equalp (redis-kit:encode-command 'ping)
                    (redis-kit:encode-command "PING"))
            :to-be t)
    (expect (redis-kit:encode-command "SET" (vector 1 2 3))
            :to-equalp
            (redis-kit:encode-command "SET" (test-octets 1 2 3)))
    (signals redis-kit:redis-client-error
      (redis-kit:encode-command "SET" (vector 1 256)))
    (signals redis-kit:redis-client-error
      (redis-kit::%ascii-octets (format nil "caf~C" #\é)))
    (signals redis-kit:redis-client-error
      (redis-kit::%octets-for-argument (list :unsupported)))
    (signals redis-kit:redis-client-error
      (redis-kit:encode-commands (list nil)))
    (signals redis-kit:redis-client-error
      (redis-kit:encode-commands (list 42))))

  (it "wraps codec failures with a client condition"
    (with-mocked-functions
        (((symbol-function 'cl-codec-kit:string-to-octets)
           (lambda (&rest arguments)
             (declare (ignore arguments))
             (error "synthetic codec failure"))))
      (signals redis-kit:redis-client-error
        (redis-kit::%utf8-octets "x")))))

(describe
    "RESP scalar and aggregate edges"
  (it "parses numeric, null, boolean, big-number, and verbatim values"
    (let ((double
            (redis-kit:reply-value
             (decode-test-reply
              (test-octets 44 43 49 46 50 53 101 43 50 13 10)))))
      (expect (< (abs (- double 125.0d0)) 1.0d-12)
              :to-be t))
    (let ((double
            (redis-kit:reply-value
             (decode-test-reply
              (test-octets 44 49 101 45 50 13 10)))))
      (expect (< (abs (- double 0.01d0)) 1.0d-12)
              :to-be t))
    (expect (redis-kit:reply-value
             (decode-test-reply (test-octets 95 13 10)))
            :to-be nil)
    (expect (redis-kit:reply-value
             (decode-test-reply (test-octets 35 102 13 10)))
            :to-be nil)
    (expect (redis-kit:reply-value
             (decode-test-reply (test-octets 40 51 13 10)))
            :to-be 3)
    (expect (equalp
             (redis-kit:redis-reply-value
              (decode-test-reply
               (test-octets 61 52 13 10
                            116 101 115 116 13 10)))
             (test-octets 116 101 115 116))
            :to-be t))

  (it "rejects malformed scalar and aggregate frames"
    (signals redis-kit:redis-protocol-error
      (decode-test-reply (test-octets 44 49 120 13 10)))
    (signals redis-kit:redis-protocol-error
      (decode-test-reply (test-octets 44 101 49 13 10)))
    (signals redis-kit:redis-protocol-error
      (decode-test-reply (test-octets 44 49 101 45 13 10)))
    (signals redis-kit:redis-protocol-error
      (decode-test-reply (test-octets 36 45 50 13 10)))
    (signals redis-kit:redis-protocol-error
      (decode-test-reply (test-octets 33 45 50 13 10)))
    (signals redis-kit:redis-protocol-error
      (decode-test-reply (test-octets 61 51 13 10 97 98 99 13 10)))
    (signals redis-kit:redis-protocol-error
      (decode-test-reply (test-octets 61 45 49 13 10)))
    (signals redis-kit:redis-protocol-error
      (decode-test-reply (test-octets 37 45 49 13 10)))
    (signals redis-kit:redis-protocol-error
      (decode-test-reply (test-octets 35 120 13 10)))
    (signals redis-kit:redis-protocol-error
      (decode-test-reply (test-octets 95 120 13 10)))
    (signals redis-kit:redis-protocol-error
      (redis-kit:decode-reply
       (test-octets 42 49 13 10
                    42 49 13 10
                    43 79 75 13 10)
       :max-depth 0))
    (signals redis-kit:redis-protocol-error
      (redis-kit:decode-reply
       (test-octets 37 49 13 10
                    43 107 13 10
                    43 118 13 10)
       :max-array-length 0))
    (signals redis-kit:redis-protocol-error
      (redis-kit::%parse-line-reply
       (codec-edge-parser (test-octets 88 79 75 13 10))
       88)))

  (it "supports raw bulk values and wraps decoding errors"
    (let ((bulk (redis-kit::make-redis-reply
                 :bulk-string
                 (test-octets 65))))
      (expect (equalp (redis-kit:reply-value bulk :decode nil)
                      (test-octets 65))
              :to-be t)
      (expect (equalp (redis-kit:reply-value bulk :decode :raw)
                      (test-octets 65))
              :to-be t)
      (with-mocked-functions
          (((symbol-function 'cl-codec-kit:octets-to-string)
             (lambda (&rest arguments)
               (declare (ignore arguments))
               (error "synthetic decoder failure"))))
        (signals redis-kit:redis-client-error
          (redis-kit:reply-value bulk))))
    (signals redis-kit:redis-client-error
      (redis-kit:reply-value nil))))
