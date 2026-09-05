(defun redis-command-specification (name)
  "Return the generated command specification named NAME, if present."
  (gethash name *redis-command-specifications*))

(defun redis-command-specification-names ()
  "Return all generated command names in deterministic display order."
  (sort (loop for name being the hash-keys of *redis-command-specifications*
              collect name)
        #'string<
        :key #'symbol-name))
