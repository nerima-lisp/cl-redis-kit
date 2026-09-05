; paredit:ignore-file length-emptiness-test -- RESP integer and double fields are strings; LENGTH is required for their empty-field checks.
(defun %parser-fail (parser message &optional cause)
  (error 'redis-protocol-error
         :message message
         :cause cause
         :position (%resp-parser-position parser)))

(defun %source-byte (source position)
  (cond
    ((consp source)
     (let ((octets (car source))
           (end (cdr source)))
       (when (< position end)
         (aref octets position))))
    ((and (vectorp source) (< position (length source)))
     (aref source position))
    ((functionp source)
     (funcall source))
    (t nil)))

(defun %parser-read-byte (parser)
  (let* ((source (%resp-parser-source parser))
         (position (%resp-parser-position parser))
         (byte (%source-byte source position)))
    (when (eq byte :eof)
      (%parser-fail parser "Unexpected end of RESP input."))
    (unless byte
      (%parser-fail parser "Unexpected end of RESP input."))
    (unless (and (integerp byte) (<= 0 byte 255))
      (%parser-fail parser "RESP input contained a non-octet byte." byte))
    (incf (%resp-parser-position parser))
    (when (> (- (%resp-parser-position parser)
                (%resp-parser-start-position parser))
             (%resp-parser-max-frame-size parser))
      (%parser-fail parser "RESP frame exceeds the configured size limit."))
    byte))

(defun %parser-read-line (parser)
  (let ((line (make-array 0 :element-type 'octet :adjustable t :fill-pointer 0)))
    (loop
      (let ((byte (%parser-read-byte parser)))
        (cond
          ((= byte 13)
           (unless (= (%parser-read-byte parser) 10)
             (%parser-fail parser "RESP line is not terminated by CRLF."))
           (return (copy-seq line)))
          ((= byte 10)
           (%parser-fail parser "RESP line contains LF without a preceding CR."))
          (t
           (when (>= (length line) (%resp-parser-max-line-length parser))
             (%parser-fail parser "RESP line exceeds the configured size limit."))
           (vector-push-extend byte line)))))))

(defun %ascii-string (parser octets)
  (let ((result (make-string (length octets))))
    (loop for byte across octets
          for index from 0
          do (unless (<= byte 127)
               (%parser-fail parser "RESP metadata contains a non-ASCII byte."))
             (setf (aref result index) (code-char byte)))
    result))

(defun %parse-integer-line (parser octets &rest arguments &key allow-negative)
  (unless (%keyword-supplied-p arguments :allow-negative)
    (setf allow-negative t))
  (let ((string (%ascii-string parser octets)))
    (when (zerop (length string))
      (%parser-fail parser "RESP integer is empty."))
    (let ((start (if (char= (char string 0) #\-) 1 0)))
      (when (and (= start 1) (not allow-negative))
        (%parser-fail parser "RESP length cannot be negative."))
      (when (= start (length string))
        (%parser-fail parser "RESP integer has no digits."))
      (loop for index from start below (length string)
            unless (digit-char-p (char string index))
              do (%parser-fail parser "RESP integer contains a non-digit."))
      (parse-integer string :junk-allowed nil))))

(defun %require-empty-line (parser line)
  (unless (zerop (length line))
    (%parser-fail parser "RESP null value must have an empty payload.")))

(defun %read-exact-octets (parser length)
  (let ((result (make-array length :element-type 'octet)))
    (dotimes (index length result)
      (setf (aref result index) (%parser-read-byte parser)))))

(defun %read-bulk (parser length)
  (when (> length (%resp-parser-max-bulk-length parser))
    (%parser-fail parser "RESP bulk string exceeds the configured size limit."))
  (let ((payload (%read-exact-octets parser length)))
    (unless (= (%parser-read-byte parser) 13)
      (%parser-fail parser "RESP bulk string is not followed by CRLF."))
    (unless (= (%parser-read-byte parser) 10)
      (%parser-fail parser "RESP bulk string is not followed by CRLF."))
    payload))

(defun %make-vector-parser (octets start end max-line-length max-bulk-length
                            max-array-length max-depth max-frame-size)
  (%make-resp-parser (cons octets end) start max-line-length max-bulk-length max-array-length
                     max-depth max-frame-size start))

(defun %stream-byte-reader (stream)
  (handler-case
      (read-byte stream nil :eof)
    (type-error ()
      (let ((character (read-char stream nil :eof)))
        (if (eq character :eof) :eof (char-code character))))))
