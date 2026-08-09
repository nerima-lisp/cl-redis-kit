(in-package #:redis-kit)

(defun %validate-tls-options (options)
  (when options
    (unless (and (listp options)
                 (handler-case (evenp (length options))
                   (type-error () nil)))
      (error 'redis-client-error
             :message "TLS options must be a proper property list."
             :cause options))
    (loop for rest = options then (cddr rest)
          while rest
          for key = (first rest)
          do (unless (and (keywordp key)
                          (case key
                            ((:verify :certificate :key :password) t)
                            (otherwise nil)))
               (error 'redis-client-error
                      :message "TLS options contain an unknown key."
                      :cause key))))
  options)

(defun %upgrade-tls-stream (stream host options)
  "Upgrade STREAM with CL+SSL using the connection's TLS OPTIONS.

CL+SSL is a direct system dependency so the TLS boundary can use its public
API without a runtime package adapter."
  (cl+ssl:make-ssl-client-stream
   stream
   :hostname host
   :verify (getf options :verify :required)
   :certificate (getf options :certificate)
   :key (getf options :key)
   :password (getf options :password)
   :external-format nil))
