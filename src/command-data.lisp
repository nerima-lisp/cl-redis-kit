(in-package #:redis-kit)

(defstruct (redis-command-spec
             (:constructor %make-redis-command-spec
                 (&key name command lambda-list arguments decode timeout
                       retry-safe-p)))
  "The data contract behind a generated Redis command function."
  name
  command
  lambda-list
  arguments
  decode
  timeout
  retry-safe-p)

(defvar *redis-command-specifications* (make-hash-table :test #'eq))

(defun register-redis-command-specification (specification)
  (check-type specification redis-command-spec)
  (setf (gethash (redis-command-spec-name specification)
                 *redis-command-specifications*)
        specification))

(defun redis-command-specification (name)
  "Return the generated command specification named NAME, if present."
  (gethash name *redis-command-specifications*))

(defun redis-command-specification-names ()
  "Return all generated command names in deterministic display order."
  (sort (loop for name being the hash-keys of *redis-command-specifications*
              collect name)
        #'string<
        :key #'symbol-name))
