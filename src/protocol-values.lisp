(defun null-reply-p (reply)
  (and (redis-reply-p reply) (eq (redis-reply-type reply) :null)))

(defun reply-error-p (reply)
  (and (redis-reply-p reply)
       (not (null (member (redis-reply-type reply)
                          '(:error :bulk-error)
                          :test #'eq)))))

(defun %decode-bulk-value (value decode)
  (if (or (null decode) (eq decode :raw))
      value
      (handler-case
          (cl-codec-kit:octets-to-string value :encoding decode)
        (error (cause)
          (error 'redis-client-error
                 :message "Unable to decode a Redis bulk value."
                 :cause cause)))))

(defun reply-value (reply &rest arguments &key decode)
  "Convert a typed REDIS-REPLY to ordinary Lisp values.

BULK-STRING values are decoded with CL-CODEC-KIT when DECODE is non-NIL;
pass NIL or :RAW to preserve their octet vectors."
  (unless (%keyword-supplied-p arguments :decode)
    (setf decode :utf-8))
  (unless (redis-reply-p reply)
    (error 'redis-client-error :message "Expected a Redis reply object."))
  (case (redis-reply-type reply)
    ((:bulk-string :bulk-error) (%decode-bulk-value (redis-reply-value reply) decode))
    ((:array :set :push)
     (mapcar (lambda (value) (reply-value value :decode decode))
             (redis-reply-value reply)))
    (:map
     (mapcar (lambda (entry)
               (cons (reply-value (car entry) :decode decode)
                     (reply-value (cdr entry) :decode decode)))
             (redis-reply-value reply)))
    (:null nil)
    (otherwise (redis-reply-value reply))))
