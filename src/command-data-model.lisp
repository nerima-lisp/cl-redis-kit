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
