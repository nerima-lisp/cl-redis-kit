(defgeneric %upgrade-tls-stream (stream host options)
  (:documentation
   "Upgrade STREAM for HOST using OPTIONS when optional TLS support is loaded."))
