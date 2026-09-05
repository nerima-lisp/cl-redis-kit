(defun %report-redis-error (condition stream)
  (write-string (redis-error-message condition) stream)
  (when (redis-error-cause condition)
    (format stream " (~A)" (redis-error-cause condition))))
