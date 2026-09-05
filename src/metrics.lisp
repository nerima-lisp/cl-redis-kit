(defstruct (redis-metrics
            (:constructor %make-redis-metrics
                (registry commands errors duration)))
  "The metrics owned by one or more Redis connections.

The metric objects themselves belong to CL-OBSERVABILITY-KIT.  This structure
only keeps the small, stable set of instruments used by the client together;
callers can inspect the underlying registry with REDIS-METRICS-REGISTRY."
  registry
  commands
  errors
  duration)

(defun make-redis-metrics (&key registry)
  "Create the standard Redis instrumentation in REGISTRY.

When REGISTRY is omitted, a new CL-OBSERVABILITY-KIT registry is created.
Metric names are deliberately aggregate: command names are not labels, so a
caller cannot accidentally turn untrusted Redis input into unbounded
cardinality."
  (let ((registry (or registry
                     (observability-kit:make-metric-registry))))
    (unless (observability-kit:metric-registry-p registry)
      (error (quote redis-client-error)
             :message "METRIC-REGISTRY must be an observability-kit metric registry."
             :cause registry))
    (%make-redis-metrics
     registry
     (observability-kit:define-counter
      registry
      redis_commands_total
      :help "Redis commands completed by the client.")
     (observability-kit:define-counter
      registry
      redis_command_errors_total
      :help "Redis commands that ended with an error.")
     (observability-kit:define-histogram
      registry
      redis_command_duration_seconds
      :help "Redis command duration in seconds."
      :unit "seconds"
      :buckets (quote (0.001d0 0.01d0 0.1d0 1.0d0 10.0d0))))))
(defun redis-metrics-snapshot (metrics)
  "Return a snapshot of the CL-OBSERVABILITY-KIT registry in METRICS."
  (check-type metrics redis-metrics)
  (observability-kit:metric-snapshot
   (redis-metrics-registry metrics)))
(defun %record-command-metrics (metrics elapsed success-p)
  (when metrics
    ;; Instrumentation must never turn a successful Redis operation into a
    ;; failed one.  The registry still enforces its own limits; those limits
    ;; are intentionally isolated from the data path here.
    (handler-case
        (progn
          (observability-kit:metric-inc
           (redis-metrics-commands metrics))
          (unless success-p
            (observability-kit:metric-inc
             (redis-metrics-errors metrics)))
          (observability-kit:metric-observe
           (redis-metrics-duration metrics)
           (max 0.0d0
                (/ elapsed
                   (float internal-time-units-per-second 1.0d0)))))
      (error (condition)
        (declare (ignore condition))
        nil))))
(defun %call-with-command-metrics (metrics thunk)
  (multiple-value-bind (outcome elapsed)
      (cl-boundary-kit:call-with-elapsed
       cl-concurrent-kit:*clock*
       (lambda ()
         (handler-case
             (list :success (multiple-value-list (funcall thunk)))
           (error (condition)
             (list :failure condition)))))
    (let ((success-p (eq (first outcome) :success)))
      (%record-command-metrics metrics elapsed success-p)
      (if success-p
          (values-list (second outcome))
          (error (second outcome))))))
