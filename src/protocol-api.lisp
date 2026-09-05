(defun %octet-vector-p (object)
  (typep object '(vector (unsigned-byte 8))))

(defun decode-reply (octets &rest arguments
                     &key start end max-line-length max-bulk-length
                       max-array-length max-depth max-frame-size)
  "Decode one RESP frame from OCTETS.

Returns two values: the REDIS-REPLY and the first unconsumed octet index."
  (unless (%keyword-supplied-p arguments :start)
    (setf start 0))
  (unless (%keyword-supplied-p arguments :max-line-length)
    (setf max-line-length *default-max-line-length*))
  (unless (%keyword-supplied-p arguments :max-bulk-length)
    (setf max-bulk-length *default-max-bulk-length*))
  (unless (%keyword-supplied-p arguments :max-array-length)
    (setf max-array-length *default-max-array-length*))
  (unless (%keyword-supplied-p arguments :max-depth)
    (setf max-depth *default-max-depth*))
  (unless (%keyword-supplied-p arguments :max-frame-size)
    (setf max-frame-size *default-max-frame-size*))
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

(defun read-reply (stream &rest arguments
                   &key max-line-length max-bulk-length max-array-length
                     max-depth max-frame-size)
  "Read exactly one RESP frame from a binary or character input stream."
  (unless (%keyword-supplied-p arguments :max-line-length)
    (setf max-line-length *default-max-line-length*))
  (unless (%keyword-supplied-p arguments :max-bulk-length)
    (setf max-bulk-length *default-max-bulk-length*))
  (unless (%keyword-supplied-p arguments :max-array-length)
    (setf max-array-length *default-max-array-length*))
  (unless (%keyword-supplied-p arguments :max-depth)
    (setf max-depth *default-max-depth*))
  (unless (%keyword-supplied-p arguments :max-frame-size)
    (setf max-frame-size *default-max-frame-size*))
  (let ((parser (%make-resp-parser (lambda () (%stream-byte-reader stream))
                                   0 max-line-length max-bulk-length
                                   max-array-length max-depth max-frame-size 0)))
    (%parse-resp-reply parser 0)))
