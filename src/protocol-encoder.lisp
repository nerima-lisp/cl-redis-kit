(defun %encodable-octet-vector-p (object)
  (and (vectorp object)
       (or (subtypep (array-element-type object) '(unsigned-byte 8))
           (every (lambda (value)
                   (and (integerp value) (<= 0 value 255)))
                 object))))

(defun %copy-octets (octets &optional (start 0) end)
  (let* ((end (or end (length octets)))
         (result (make-array (- end start) :element-type 'octet)))
    (replace result octets :start2 start :end2 end)
    result))

(defun %ascii-octets (string)
  (let ((result (make-array (length string) :element-type 'octet)))
    (loop for character across string
          for index from 0
          do (let ((code (char-code character)))
               (unless (<= 0 code 127)
                 (error 'redis-client-error
                        :message "RESP command metadata must be ASCII."))
               (setf (aref result index) code)))
    result))

(defun %utf8-octets (string)
  (handler-case
      (cl-codec-kit:string-to-octets string :encoding :utf-8)
    (error (cause)
      (error 'redis-client-error
             :message "Unable to encode a Redis argument as UTF-8."
             :cause cause))))

(defun %octets-for-argument (argument)
  (cond
    ((%encodable-octet-vector-p argument)
     (%copy-octets argument))
    ((stringp argument)
     (%utf8-octets argument))
    ((symbolp argument)
     (%utf8-octets (string-upcase (symbol-name argument))))
    ((numberp argument)
     (%utf8-octets (write-to-string argument :base 10 :radix nil)))
    (t
     (error 'redis-client-error
            :message "Redis arguments must be strings, octets, symbols, or numbers."
            :cause argument))))

(defun %append-octets (target source)
  (loop for byte across source do (vector-push-extend byte target))
  target)

(defun %append-ascii (target string)
  (%append-octets target (%ascii-octets string)))

(defun %append-crlf (target)
  (vector-push-extend 13 target)
  (vector-push-extend 10 target)
  target)

(defun encode-command (command &rest arguments)
  "Encode one Redis command as an array of bulk strings.

COMMAND and ARGUMENTS accept strings, octet vectors, symbols, or numbers.
The returned vector is suitable for writing to a binary socket stream."
  (let* ((parts (mapcar #'%octets-for-argument (cons command arguments)))
         (result (make-array 0 :element-type 'octet :adjustable t :fill-pointer 0)))
    (%append-ascii result (format nil "*~D" (length parts)))
    (%append-crlf result)
    (dolist (part parts)
      (%append-ascii result (format nil "$~D" (length part)))
      (%append-crlf result)
      (%append-octets result part)
      (%append-crlf result))
    (copy-seq result)))

(defun encode-commands (commands)
  "Encode a sequence of command lists into one pipelined RESP request."
  (let ((result (make-array 0 :element-type 'octet :adjustable t :fill-pointer 0)))
    (dolist (command commands (copy-seq result))
      (unless (consp command)
        (error 'redis-client-error
               :message "Each pipeline command must be a non-empty list."))
      (%append-octets result (apply #'encode-command command)))))
