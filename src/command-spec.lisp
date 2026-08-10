; paredit:ignore-file macro-multiple-evaluation -- Macro arguments are validated at expansion time; quoted metadata is data and each generated runtime option is consumed once.
(in-package #:redis-kit)

(defmacro define-redis-command
    (name command lambda-list &key (arguments nil arguments-supplied-p)
                              (decode :utf-8) timeout retry-safe-p)
  "Define a typed Redis command from its wire-level specification.

COMMAND is the Redis command name, LAMBDA-LIST describes the public
arguments after the connection, and ARGUMENTS is a form producing the list
sent to Redis.  The generated function delegates to the same execution,
timeout, retry, and decoding path as EXECUTE, so command declarations do not
create a second wire or protocol path.

RETRY-SAFE-P is deliberately part of the specification.  A command may use
the connection retry policy only when its caller has established that replay
is safe for the application."
  (check-type name symbol)
  (check-type command string)
  (unless arguments-supplied-p
    (error "DEFINE-REDIS-COMMAND requires an :ARGUMENTS form."))
  `(progn
     (eval-when (:compile-toplevel :load-toplevel :execute)
       (register-redis-command-specification
        (%make-redis-command-spec
         :name ',name
         :command ,command
         :lambda-list ',lambda-list
         :arguments ',arguments
         :decode ',decode
         :timeout ',timeout
         :retry-safe-p ',retry-safe-p)))
     (defun ,name (connection ,@lambda-list)
       (%command-value connection ,command ,arguments
                       :decode ,decode
                       :timeout ,timeout
                       :retry-safe-p ,retry-safe-p))))
