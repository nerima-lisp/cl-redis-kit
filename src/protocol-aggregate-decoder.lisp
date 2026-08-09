(in-package #:redis-kit)

(defun %parse-count (parser line kind)
  (let ((count (%parse-integer-line parser line :allow-negative nil)))
    (when (> count (%resp-parser-max-array-length parser))
      (%parser-fail parser (format nil "RESP ~A exceeds the configured size limit." kind)))
    count))

(defun %parse-aggregate (parser count depth)
  (loop repeat count collect (%parse-resp-reply parser (1+ depth))))

(defun %parse-map-entries (parser count depth)
  (loop repeat count
        collect (cons (%parse-resp-reply parser (1+ depth))
                      (%parse-resp-reply parser (1+ depth)))))

(defun %parse-array-reply (parser depth)
  (let ((count (%parse-integer-line parser (%parser-read-line parser))))
    (cond
      ((= count -1)
       (make-redis-reply :null nil))
      ((minusp count)
       (%parser-fail parser "RESP array length is invalid."))
      ((> count (%resp-parser-max-array-length parser))
       (%parser-fail parser "RESP array exceeds the configured size limit."))
      (t
       (make-redis-reply :array
                         (%parse-aggregate parser count depth))))))

(defun %parse-counted-collection-reply (parser type depth)
  (let* ((kind (case type
                 (37 "map")
                 (126 "set")
                 (62 "push")
                 (otherwise
                  (%parser-fail parser "Unknown RESP collection type." type))))
         (count (%parse-count parser (%parser-read-line parser) kind)))
    (case type
      (37
       (make-redis-reply :map (%parse-map-entries parser count depth)))
      (126
       (make-redis-reply :set (%parse-aggregate parser count depth)))
      (62
       (make-redis-reply :push (%parse-aggregate parser count depth))))))

(defun %parse-attribute-reply (parser depth)
  (let* ((count (%parse-count parser (%parser-read-line parser) "attribute"))
         (attributes (%parse-map-entries parser count depth))
         (value (%parse-resp-reply parser depth)))
    (make-redis-reply (redis-reply-type value)
                      (redis-reply-value value)
                      :attributes attributes)))

(defun %parse-resp-reply (parser depth)
  (when (> depth (%resp-parser-max-depth parser))
    (%parser-fail parser "RESP nesting exceeds the configured depth limit."))
  (let ((type (%parser-read-byte parser)))
    (case type
      ((43 45 58 44 40)
       (%parse-line-reply parser type))
      ((36 33 61)
       (%parse-length-prefixed-reply parser type))
      (42
       (%parse-array-reply parser depth))
      (95
       (%parse-null-reply parser))
      (35
       (%parse-boolean-reply parser))
      ((37 126 62)
       (%parse-counted-collection-reply parser type depth))
      (124
       (%parse-attribute-reply parser depth))
      (otherwise
       (%parser-fail parser "Unknown RESP type byte." type)))))
