; paredit:ignore-file leftover-inspect-call -- CL-WEAVE's DESCRIBE is the BDD test DSL, not a debugger inspection call.
(in-package #:redis-kit/test)

(describe
    "RESP codec"
  (it "encodes commands as binary-safe RESP arrays"
    (expect (redis-kit:encode-command "PING" "hello")
            :to-equalp
            (test-octets
             42 50 13 10
             36 52 13 10 80 73 78 71 13 10
             36 53 13 10 104 101 108 108 111 13 10))
    (expect (redis-kit:encode-command "SET" (test-octets 65 0 66))
            :to-equalp
            (test-octets
             42 50 13 10
             36 51 13 10 83 69 84 13 10
             36 51 13 10 65 0 66 13 10)))
  (it "combines pipelined commands without separators"
    (expect (redis-kit:encode-commands
              (list (list "PING") (list "INCR" "n")))
            :to-equalp
            (concatenate '(vector (unsigned-byte 8))
                         (redis-kit:encode-command "PING")
                         (redis-kit:encode-command "INCR" "n"))))
  (it "decodes RESP2 frames and supports a bounded suffix"
    (let ((bytes (test-octets 43 79 75 13 10 58 52 50 13 10)))
      (multiple-value-bind (reply next) (redis-kit:decode-reply bytes)
        (expect (redis-kit:redis-reply-type reply) :to-be :simple-string)
        (expect (redis-kit:reply-value reply) :to-equal "OK")
        (expect next :to-be 5)
        (multiple-value-bind (integer-reply final)
            (redis-kit:decode-reply bytes :start next)
          (expect (redis-kit:redis-reply-type integer-reply) :to-be :integer)
          (expect (redis-kit:reply-value integer-reply) :to-be 42)
          (expect final :to-be (length bytes))))))
  (it "preserves binary bulk values and decodes UTF-8 explicitly"
    (let ((binary (decode-test-reply
                   (test-octets 36 51 13 10 65 0 66 13 10)))
          (snow (decode-test-reply
                 (test-octets 36 51 13 10 226 152 131 13 10))))
      (expect (redis-kit:reply-value binary :decode nil)
              :to-equalp
              (test-octets 65 0 66))
      (expect (redis-kit:reply-value snow) :to-equal "☃")))
  (it "handles null, arrays, errors, and RESP3 values"
    (let ((null-bulk (decode-test-reply (test-octets 36 45 49 13 10)))
          (null-array (decode-test-reply (test-octets 42 45 49 13 10)))
          (bulk-error (decode-test-reply
                       (test-octets 33 51 13 10 69 82 82 13 10)))
          (boolean (decode-test-reply (test-octets 35 116 13 10)))
          (map (decode-test-reply
                (test-octets 37 49 13 10
                             43 107 13 10
                             58 50 13 10)))
          (set (decode-test-reply
                (test-octets 126 50 13 10 58 49 13 10 58 50 13 10)))
          (push-reply (decode-test-reply
                 (test-octets 62 50 13 10
                              43 109 13 10
                              43 112 13 10)))
          (attributes (decode-test-reply
                       (test-octets 124 49 13 10
                                    43 109 13 10
                                    43 118 13 10
                                    43 79 75 13 10))))
      (expect (redis-kit:null-reply-p null-bulk) :to-be t)
      (expect (redis-kit:null-reply-p null-array) :to-be t)
      (expect (redis-kit:reply-error-p bulk-error) :to-be t)
      (expect (redis-kit:null-reply-p nil) :to-be nil)
      (expect (redis-kit:reply-error-p nil) :to-be nil)
      (expect (redis-kit:reply-value boolean) :to-be t)
      (expect (redis-kit:reply-value map) :to-equal '(("k" . 2)))
      (expect (redis-kit:reply-value set) :to-equal '(1 2))
      (expect (redis-kit:reply-value push-reply) :to-equal '("m" "p"))
      (expect (redis-kit:reply-value attributes) :to-equal "OK")
      (expect (length (redis-kit:redis-reply-attributes attributes)) :to-be 1)))
  (it "parses RESP3 doubles without using the Lisp reader"
    (let ((integer (decode-test-reply
                    (test-octets 44 52 50 13 10)))
          (positive (decode-test-reply
                     (test-octets 44 49 46 53 13 10)))
          (scientific (decode-test-reply
                       (test-octets 44 45 50 46 53 101 49 13 10)))
          (positive-infinity (decode-test-reply
                              (test-octets 44 105 110 102 13 10)))
          (negative-infinity (decode-test-reply
                              (test-octets 44 45 105 110 102 13 10)))
          (not-a-number (decode-test-reply
                         (test-octets 44 110 97 110 13 10))))
      (expect (redis-kit:redis-reply-type integer) :to-be :double)
      (expect (redis-kit:reply-value integer) :to-be 42.0d0)
      (expect (redis-kit:redis-reply-type positive) :to-be :double)
      (expect (< (abs (- (redis-kit:reply-value positive) 1.5d0)) 1d-12)
              :to-be t)
      (expect (< (abs (- (redis-kit:reply-value scientific) -25.0d0)) 1d-12)
              :to-be t)
      (expect (redis-kit:reply-value positive-infinity)
              :to-be most-positive-double-float)
      (expect (redis-kit:reply-value negative-infinity)
              :to-be most-negative-double-float)
      (expect (redis-kit:reply-value not-a-number) :to-be :nan))
    (signals redis-kit:redis-protocol-error
      (decode-test-reply (test-octets 44 49 101 13 10)))
    (signals redis-kit:redis-protocol-error
      (decode-test-reply
       (test-octets 44 49 101 57 57 57 57 57 57 13 10))))
  (it "rejects malformed, truncated, out-of-bounds, and too-deep frames"
    (signals redis-kit:redis-protocol-error
      (redis-kit:decode-reply (test-octets 43 79 75 10)))
    (signals redis-kit:redis-protocol-error
      (redis-kit:decode-reply (test-octets 36 51 13 10 65)))
    (signals redis-kit:redis-client-error
      (redis-kit:decode-reply (test-octets 43 79 75 13 10)
                               :start 4
                               :end 2))
    (signals redis-kit:redis-protocol-error
      (redis-kit:decode-reply
       (test-octets 42 49 13 10 43 79 75 13 10)
       :max-depth 0))))
