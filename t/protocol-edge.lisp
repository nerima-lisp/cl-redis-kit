; paredit:ignore-file leftover-inspect-call -- CL-WEAVE's DESCRIBE is the BDD test DSL, not a debugger inspection call.
(in-package #:redis-kit/test)

(describe
    "RESP input validation"
  (it "validates octet input and bounds"
    (signals redis-kit:redis-client-error
      (redis-kit:decode-reply (vector 43 79 75 13 10)))
    (signals redis-kit:redis-client-error
      (redis-kit:decode-reply
       (test-octets 43 79 75 13 10)
       :start -1))
    (signals redis-kit:redis-client-error
      (redis-kit:decode-reply
       (test-octets 43 79 75 13 10)
       :end 6))
    (signals redis-kit:redis-client-error
      (redis-kit:decode-reply
       (test-octets 43 79 75 13 10)
       :start 4
       :end 3)))

  (it "enforces line, bulk, aggregate, and frame limits"
    (signals redis-kit:redis-protocol-error
      (redis-kit:decode-reply
       (test-octets 43 79 75 13 10)
       :max-line-length 1))
    (signals redis-kit:redis-protocol-error
      (redis-kit:decode-reply
       (test-octets 36 51 13 10 97 98 99 13 10)
       :max-bulk-length 2))
    (signals redis-kit:redis-protocol-error
      (redis-kit:decode-reply
       (test-octets 42 49 13 10 43 79 75 13 10)
       :max-array-length 0))
    (signals redis-kit:redis-protocol-error
      (redis-kit:decode-reply
       (test-octets 43 79 75 13 10)
       :max-frame-size 1))))

(describe
    "RESP scalar edge cases"
  (it "rejects malformed doubles"
    (signals redis-kit:redis-protocol-error
      (decode-test-reply (test-octets 44 13 10)))
    (signals redis-kit:redis-protocol-error
      (decode-test-reply (test-octets 44 43 13 10)))
    (signals redis-kit:redis-protocol-error
      (decode-test-reply (test-octets 44 49 101 13 10))))

  (it "decodes a finite double"
    (expect (redis-kit:reply-value
             (decode-test-reply
              (test-octets 44 49 46 50 53 13 10)))
            :to-satisfy
            (lambda (value)
              (and (numberp value)
                   (< (abs (- value 1.25)) 1d-9))))))

(describe
    "RESP reader primitives"
  (it "rejects truncated, non-ASCII, and malformed metadata"
    (flet ((parser (source &optional (max-bulk-length 32) (max-depth 256))
             (redis-kit::%make-resp-parser
              source 0 32 max-bulk-length 32 8 max-depth 0)))
      (expect (redis-kit::%source-byte
               (cons (test-octets 7) 1) 0)
              :to-be 7)
      (expect (redis-kit::%source-byte
               (cons (test-octets 7) 1) 1)
              :to-be nil)
      (expect (redis-kit::%source-byte (vector 8) 0) :to-be 8)
      (expect (redis-kit::%source-byte (lambda () 9) 0) :to-be 9)
      (expect (redis-kit::%source-byte :invalid 0) :to-be nil)
      (signals redis-kit:redis-protocol-error
        (redis-kit::%parser-read-byte (parser (lambda () :eof))))
      (signals redis-kit:redis-protocol-error
        (redis-kit::%parser-read-byte (parser nil)))
      (signals redis-kit:redis-protocol-error
        (redis-kit::%parser-read-byte
         (parser (cons (vector 256) 1))))
      (signals redis-kit:redis-protocol-error
        (redis-kit::%parser-read-byte
         (parser (vector #\A))))
      (signals redis-kit:redis-protocol-error
        (redis-kit::%parser-read-line
         (parser (test-octets 43 79 75 10))))
      (signals redis-kit:redis-protocol-error
        (redis-kit::%parser-read-line
         (parser (test-octets 43 79 75 13 88))))
      (signals redis-kit:redis-protocol-error
        (redis-kit::%parser-read-line
         (parser (test-octets 43 13))))
      (signals redis-kit:redis-protocol-error
        (redis-kit::%ascii-string (parser nil) (test-octets 200)))
      (expect (redis-kit::%parse-integer-line
               (parser nil) (test-octets 45 50))
              :to-be -2)
      (signals redis-kit:redis-protocol-error
        (redis-kit::%parse-integer-line (parser nil) (test-octets)))
      (signals redis-kit:redis-protocol-error
        (redis-kit::%parse-integer-line (parser nil) (test-octets 45)))
      (signals redis-kit:redis-protocol-error
        (redis-kit::%parse-integer-line
         (parser nil) (test-octets 45 49) :allow-negative nil))
      (signals redis-kit:redis-protocol-error
        (redis-kit::%parse-integer-line (parser nil) (test-octets 49 120)))
      (signals redis-kit:redis-protocol-error
        (redis-kit::%require-empty-line (parser nil) (test-octets 120)))
      (signals redis-kit:redis-protocol-error
        (redis-kit::%read-bulk
         (parser (test-octets 97 10)) 1))
      (signals redis-kit:redis-protocol-error
        (redis-kit::%read-bulk
         (parser (test-octets 97 13 88)) 1))
      (signals redis-kit:redis-protocol-error
        (redis-kit::%read-bulk
         (parser (test-octets 97 13 10) 0) 1))
      (signals redis-kit:redis-protocol-error
        (redis-kit::%parse-counted-collection-reply (parser nil) 63 0))))

  (it "rejects a negative array length"
    (signals redis-kit:redis-protocol-error
      (redis-kit:decode-reply
       (test-octets 42 45 50 13 10))))

  (it "reads RESP from character streams through the byte fallback"
    (let ((stream
            (make-string-input-stream
             (format nil "+OK~C~C" #\Return #\Linefeed))))
      (expect (redis-kit:reply-value (redis-kit:read-reply stream))
              :to-equal
              "OK")
      (expect (redis-kit::%stream-byte-reader
               (make-string-input-stream ""))
              :to-be
              :eof)))

  (it "passes explicit read limits through the public reader"
    (let ((stream
            (make-string-input-stream
             (format nil "+OK~C~C" #\Return #\Linefeed))))
      (expect (redis-kit:reply-value
               (redis-kit:read-reply
                stream
                :max-line-length 32
                :max-bulk-length 32
                :max-array-length 32
                :max-depth 8
                :max-frame-size 32))
              :to-equal
              "OK"))))
