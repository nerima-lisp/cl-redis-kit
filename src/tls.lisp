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

(defmethod %upgrade-tls-stream ((stream t) host options)
  (declare (ignore stream host options))
  (error 'redis-client-error
         :message "TLS support is not loaded. Load the cl-redis-kit/tls system."
         :cause :tls-unavailable))
