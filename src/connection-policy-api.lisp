(defgeneric %call-with-command-policy/k
    (connection command thunk on-success on-error retry-safe-p)
  (:documentation
   "Run a command through the configured retry policy when available.

The core system deliberately does not require a resilience implementation.
The optional CL-REDIS-KIT/RESILIENCE system specializes this operation with
CL-RESILIENCE-KIT.  THUNK is invoked at most once by the core method; its
values are passed to ON-SUCCESS and errors are passed to ON-ERROR."))
