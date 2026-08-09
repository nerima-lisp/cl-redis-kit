(in-package #:redis-kit)

;;;; RESP is deliberately parsed as octets.  Converting a bulk string to a
;;;; Lisp string is an explicit policy at the public reply-value boundary.

(deftype octet () '(unsigned-byte 8))

(deftype octet-vector () '(vector (unsigned-byte 8)))

(defparameter *default-max-line-length* 16384
  "Maximum number of bytes in one RESP line.")

(defparameter *default-max-bulk-length* (* 512 1024 1024)
  "Maximum RESP bulk-string payload accepted by the parser.")

(defparameter *default-max-array-length* 1000000
  "Maximum number of elements accepted in an aggregate reply.")

(defparameter *default-max-depth* 128
  "Maximum nesting depth accepted in an aggregate reply.")

(defparameter *default-max-frame-size* (* 512 1024 1024)
  "Maximum total size of one RESP frame accepted by the parser.")

(defstruct (redis-reply
           (:constructor make-redis-reply (type value &key attributes)))
  (type :null :type keyword :read-only t)
  value
  attributes)

(defstruct (%resp-parser
           (:constructor %make-resp-parser
               (source position max-line-length max-bulk-length
                max-array-length max-depth max-frame-size start-position)))
  source
  (position 0 :type fixnum)
  max-line-length
  max-bulk-length
  max-array-length
  max-depth
  max-frame-size
  (start-position 0 :type fixnum))
