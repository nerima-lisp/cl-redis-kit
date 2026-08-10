(in-package #:redis-kit)

(defmethod %upgrade-tls-stream ((stream stream) host options)
  "Upgrade STREAM with cl+ssl using the connection's TLS OPTIONS."
  (cl+ssl:make-ssl-client-stream
   stream
   :hostname host
   :verify (getf options :verify :required)
   :certificate (getf options :certificate)
   :key (getf options :key)
   :password (getf options :password)
   :external-format nil))
