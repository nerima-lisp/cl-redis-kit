(in-package #:redis-kit)

(defun %decimal-digit-value (character)
  (and (char>= character #\0)
       (char<= character #\9)
       (- (char-code character) (char-code #\0))))

(defun %parse-double (parser line)
  (let ((string (%ascii-string parser line)))
    (cond
      ((string-equal string "inf") most-positive-double-float)
      ((string-equal string "-inf") most-negative-double-float)
      ;; Common Lisp has no portable NaN literal.  Preserve the RESP value
      ;; explicitly on implementations without an implementation-specific
      ;; NaN constructor rather than accidentally signalling a reader error.
      ((string-equal string "nan") :nan)
      (t
       (let ((index 0)
             (size (length string))
             (sign 1.0d0)
             (mantissa 0.0d0)
             (digit-count 0)
             (fraction-digits 0)
             (exponent 0)
             (exponent-sign 1))
         (when (< index size)
           (case (char string index)
             (#\+ (incf index))
             (#\- (setf sign -1.0d0)
                   (incf index))))
         (loop while (and (< index size)
                          (%decimal-digit-value (char string index)))
               do (let ((digit (%decimal-digit-value (char string index))))
                    (setf mantissa (+ (* mantissa 10.0d0) digit))
                    (incf digit-count)
                    (incf index)))
         (when (and (< index size)
                    (char= (char string index) #\.))
           (incf index)
           (loop while (and (< index size)
                            (%decimal-digit-value (char string index)))
                 do (let ((digit (%decimal-digit-value (char string index))))
                      (setf mantissa (+ (* mantissa 10.0d0) digit))
                      (incf digit-count)
                      (incf fraction-digits)
                      (incf index))))
         (unless (plusp digit-count)
           (%parser-fail parser "RESP double is invalid."))
         (when (and (< index size)
                    (find (char string index) "eE" :test #'char=))
           (incf index)
           (when (< index size)
             (case (char string index)
               (#\+ (incf index))
               (#\- (setf exponent-sign -1)
                     (incf index))))
           (let ((exponent-digits 0))
             (loop while (and (< index size)
                              (%decimal-digit-value (char string index)))
                   do (let ((digit (%decimal-digit-value (char string index))))
                        (setf exponent (+ (* exponent 10) digit))
                        (incf exponent-digits)
                        (incf index)))
             (unless (plusp exponent-digits)
               (%parser-fail parser "RESP double is invalid."))))
         (unless (= index size)
           (%parser-fail parser "RESP double is invalid."))
         (handler-case
             (* sign mantissa
                (expt 10.0d0
                      (- (* exponent-sign exponent) fraction-digits)))
           (error (cause)
             (%parser-fail parser "RESP double is invalid." cause))))))))

(defun %parse-line-reply (parser type)
  (let ((line (%parser-read-line parser)))
    (case type
      (43
       (make-redis-reply :simple-string (%ascii-string parser line)))
      (45
       (make-redis-reply :error (%ascii-string parser line)))
      (58
       (make-redis-reply :integer (%parse-integer-line parser line)))
      (44
       (make-redis-reply :double (%parse-double parser line)))
      (40
       (make-redis-reply :big-number (%parse-integer-line parser line)))
      (otherwise
       (%parser-fail parser "Unknown RESP line type." type)))))

(defun %parse-nullable-bulk-reply (parser type)
  (let* ((line (%parser-read-line parser))
         (length (%parse-integer-line parser line))
         (reply-type (if (= type 36) :bulk-string :bulk-error))
         (kind (if (= type 36) "bulk string" "bulk error")))
    (cond
      ((= length -1)
       (make-redis-reply :null nil))
      ((minusp length)
       (%parser-fail parser (format nil "RESP ~A length is invalid." kind)))
      (t
       (make-redis-reply reply-type (%read-bulk parser length))))))

(defun %parse-verbatim-reply (parser)
  (let ((length (%parse-integer-line parser (%parser-read-line parser))))
    (cond
      ((minusp length)
       (%parser-fail parser "RESP verbatim string length is invalid."))
      ((< length 4)
       (%parser-fail parser "RESP verbatim string is shorter than its format."))
      (t
       (make-redis-reply :verbatim-string (%read-bulk parser length))))))

(defun %parse-length-prefixed-reply (parser type)
  (if (= type 61)
      (%parse-verbatim-reply parser)
      (%parse-nullable-bulk-reply parser type)))

(defun %parse-null-reply (parser)
  (%require-empty-line parser (%parser-read-line parser))
  (make-redis-reply :null nil))

(defun %parse-boolean-reply (parser)
  (let ((line (%ascii-string parser (%parser-read-line parser))))
    (cond
      ((string= line "t")
       (make-redis-reply :boolean t))
      ((string= line "f")
       (make-redis-reply :boolean nil))
      (t
       (%parser-fail parser "RESP boolean must be t or f.")))))
