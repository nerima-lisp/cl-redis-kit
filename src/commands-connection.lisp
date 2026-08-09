(in-package #:redis-kit)

(define-redis-command auth "AUTH" (password &key username timeout)
  :arguments (if username (list username password) (list password))
  :timeout timeout)

(define-redis-command select "SELECT" (database &key timeout)
  :arguments (list database)
  :timeout timeout)

(defun hello (connection &rest arguments)
  (multiple-value-bind (values options)
      (%single-command-argument arguments "HELLO")
    (%command-value connection "HELLO"
                    (list (if values (first values) 3))
                    :timeout (getf options :timeout)
                    :retry-safe-p (getf options :retry-safe-p))))

(defun ping (connection &rest arguments)
  (multiple-value-bind (values options)
      (%single-command-argument arguments "PING")
    (%command-value connection "PING"
                    (when values (list (first values)))
                    :timeout (getf options :timeout)
                    :retry-safe-p (getf options :retry-safe-p))))

(defun quit (connection &key timeout)
  (unwind-protect
       (%command-value connection "QUIT" nil :timeout timeout)
    (close-connection connection)))
