(in-package #:redis-kit)

(defun decode-reply (octets &key (start 0) end
                             (max-line-length *default-max-line-length*)
                             (max-bulk-length *default-max-bulk-length*)
                             (max-array-length *default-max-array-length*)
                             (max-depth *default-max-depth*)
                             (max-frame-size *default-max-frame-size*))
  "Decode one RESP frame from OCTETS.

Returns two values: the REDIS-REPLY and the first unconsumed octet index."
  (unless (%octet-vector-p octets)
    (error 'redis-client-error :message "RESP input must be an octet vector."))
  (let ((end (or end (length octets))))
    (unless (and (<= 0 start end) (<= end (length octets)))
      (error 'redis-client-error :message "Invalid RESP input bounds."))
    (let ((parser (%make-vector-parser octets start end max-line-length
                                       max-bulk-length max-array-length max-depth
                                       max-frame-size)))
      (values (%parse-resp-reply parser 0)
              (%resp-parser-position parser)))))

(defun read-reply (stream &key
                           (max-line-length *default-max-line-length*)
                           (max-bulk-length *default-max-bulk-length*)
                           (max-array-length *default-max-array-length*)
                           (max-depth *default-max-depth*)
                           (max-frame-size *default-max-frame-size*))
  "Read exactly one RESP frame from a binary or character input stream."
  (let ((parser (%make-resp-parser (lambda () (%stream-byte-reader stream))
                                   0 max-line-length max-bulk-length
                                   max-array-length max-depth max-frame-size 0)))
    (%parse-resp-reply parser 0)))
