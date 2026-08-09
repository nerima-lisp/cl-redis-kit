(in-package #:redis-kit)

(defun %timeout-duration (seconds)
  (when seconds
    (multiple-value-bind (whole fraction) (floor seconds)
      (let ((nanos (round (* fraction 1000000000))))
        (if (= nanos 1000000000)
            (cl-date-kit:duration-of-seconds (1+ whole) 0)
            (cl-date-kit:duration-of-seconds whole nanos))))))

(defun %close-transport (connection)
  (let ((stream (%connection-stream connection))
        (socket (%connection-socket connection)))
    (setf (%connection-stream connection) nil
          (%connection-socket connection) nil)
    (when stream
      (handler-case
          (close stream :abort t)
        (error (condition)
          (declare (ignore condition))
          nil)))
    (when socket
      (handler-case
          (usocket:socket-close socket)
        (error (condition)
          (declare (ignore condition))
          nil)))))

(defun %invalidate-connection (connection)
  (%close-transport connection)
  (setf (connection-state connection) :broken)
  connection)

(defun %call-with-timeout (connection timeout thunk)
  (let ((seconds (or timeout (connection-timeout connection))))
    (handler-case
        (if seconds
            (cl-concurrent-kit:with-timeout (%timeout-duration seconds)
              (funcall thunk))
            (funcall thunk))
      (cl-concurrent-kit:operation-timed-out (cause)
        (%invalidate-connection connection)
        (error 'redis-timeout-error
               :message "Redis operation timed out; the connection was closed."
               :cause cause)))))

(defun %establish-transport (connection)
  (unless (%connection-custom-boundary-p connection)
    (let ((socket
            (usocket:socket-connect
             (connection-host connection)
             (connection-port connection)
             :protocol :stream
             :element-type '(unsigned-byte 8)
             :connection-timeout (%connection-connect-timeout connection)
             :read-timeout (%connection-read-timeout connection)
             :nodelay t)))
      (setf (%connection-socket connection) socket
            (%connection-stream connection) (usocket:socket-stream socket))
      (when (connection-tls connection)
        (setf (%connection-stream connection)
              (%upgrade-tls-stream
               (%connection-stream connection)
               (connection-host connection)
               (connection-tls connection))))))
  connection)

(defun %unsupported-hello-error-p (condition)
  (and (string-equal (or (redis-error-code condition) "") "ERR")
       (let ((message (string-downcase (redis-error-message condition))))
         (not (null (or (search "unknown command" message)
                        (search "unsupported command" message)
                        (search "unknown or unsupported" message)))))))

(defun %reply-error-text (reply)
  (let ((value (reply-value reply :decode :utf-8)))
    (if (stringp value) value (princ-to-string value))))

(defun %server-error-code (message)
  (let ((space (position #\Space message)))
    (if space (subseq message 0 space) message)))

(defun %check-server-reply (reply)
  (if (reply-error-p reply)
      (let ((message (%reply-error-text reply)))
        (error 'redis-server-error
               :message message
               :code (%server-error-code message)
               :reply reply))
      reply))

(defun %normalize-boundary-result (result count)
  (cond
    ((= count 1)
     (cond
       ((redis-reply-p result) result)
       ((and (listp result) (= (length result) 1)
             (redis-reply-p (first result)))
        (first result))
       (t
        (error 'redis-connection-error
               :message "The network boundary returned an invalid Redis reply."
               :cause result))))
    ((and (listp result)
          (= (length result) count)
          (every #'redis-reply-p result))
     result)
    (t
     (error 'redis-connection-error
            :message "The network boundary returned an invalid Redis pipeline."
            :cause result))))

(defun %request-replies (connection octets count timeout)
  (unless (member (connection-state connection) '(:opening :ready) :test #'eq)
    (error 'redis-connection-error
           :message "The Redis connection is not open."
           :cause (connection-state connection)))
  (handler-case
      (%call-with-timeout
       connection timeout
       (lambda ()
         (%normalize-boundary-result
          (cl-boundary-kit:network-boundary-request
           (connection-network-boundary connection)
           (list :bytes octets :replies count)
           :timeout timeout)
          count)))
    (redis-timeout-error (condition)
      (error condition))
    (redis-connection-error (condition)
      (%invalidate-connection connection)
      (error condition))
    (redis-error (condition)
      (error condition))
    (error (cause)
      (%invalidate-connection connection)
      (error 'redis-connection-error
             :message "Redis network boundary request failed."
             :cause cause))))

(defun %socket-boundary-request (connection request timeout)
  (declare (ignore timeout))
  (let ((stream (%connection-stream connection))
        (octets (getf request :bytes))
        (count (getf request :replies)))
    (unless (and stream (vectorp octets) (integerp count) (plusp count))
      (error 'redis-connection-error
             :message "The socket boundary received an invalid request."
             :cause request))
    (handler-case
        (progn
          (write-sequence octets stream)
          (finish-output stream)
          (loop with replies = nil
                with normal-count = 0
                while (< normal-count count)
                for reply = (read-reply stream)
                do (if (eq (redis-reply-type reply) :push)
                       (if (%connection-push-handler connection)
                           (funcall (%connection-push-handler connection) reply)
                           (progn
                             (push reply (%connection-pushes connection))
                             (when (> (length (%connection-pushes connection))
                                      (%connection-max-pushes connection))
                               (setf (%connection-pushes connection)
                                     (subseq (%connection-pushes connection)
                                             0 (%connection-max-pushes connection))))))
                       (progn
                         (incf normal-count)
                         (push reply replies)))
                finally
                   (return (if (= count 1)
                               (first replies)
                               (nreverse replies)))))
      (redis-error (condition)
        (%invalidate-connection connection)
        (error condition))
      (error (cause)
        (%invalidate-connection connection)
        (error 'redis-connection-error
               :message "Redis socket I/O failed."
               :cause cause)))))

(defun %raw-command (connection command arguments &key timeout)
  (%request-replies connection
                    (apply #'encode-command command arguments)
                    1
                    timeout))
