(in-package #:redis-kit)

(define-condition redis-error (error)
  ((message
    :initarg :message
    :reader redis-error-message
    :initform "Redis operation failed.")
   (cause
    :initarg :cause
    :reader redis-error-cause
    :initform nil))
  (:report
   (lambda (condition stream)
     (write-string (redis-error-message condition) stream)
     (when (redis-error-cause condition)
       (format stream " (~A)" (redis-error-cause condition))))))

(define-condition redis-client-error (redis-error) ())

(define-condition redis-protocol-error (redis-client-error)
  ((position
    :initarg :position
    :reader redis-error-position
    :initform nil)))

(define-condition redis-connection-error (redis-client-error) ())

(define-condition redis-timeout-error (redis-connection-error) ())

(define-condition redis-server-error (redis-error)
  ((code
    :initarg :code
    :reader redis-error-code
    :initform nil)
   (reply
    :initarg :reply
    :reader redis-error-reply
    :initform nil)))
