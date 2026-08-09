; paredit:ignore-file leftover-inspect-call -- CL-WEAVE's DESCRIBE is the BDD test DSL, not a debugger inspection call.
(in-package #:redis-kit/test)

(defun make-error-boundary ()
  (cl-boundary-kit:make-network-boundary
   :request-fn
   (lambda (request &key timeout)
     (declare (ignore request timeout))
     (test-error-reply "ERR fixture"))))

(defun metric-snapshot-by-name (snapshots name)
  (find name snapshots
        :key #'observability-kit:metric-snapshot-name
        :test #'string=))

(describe
    "observability instrumentation"
  (it "rejects registries from another abstraction"
    (signals redis-kit:redis-client-error
      (redis-kit:make-redis-metrics :registry :not-a-registry)))

  (it "isolates instrumentation failures from command results"
    (let ((metrics (redis-kit:make-redis-metrics)))
      (with-mocked-functions
          (((symbol-function 'observability-kit:metric-inc)
             (lambda (&rest arguments)
               (declare (ignore arguments))
               (error "synthetic metric failure"))))
        (expect (redis-kit::%record-command-metrics metrics 0 t)
                :to-be nil))))

  (it "uses the boundary clock and preserves multiple return values"
    (let* ((clock (cl-boundary-kit:make-fake-clock))
           (metrics (redis-kit:make-redis-metrics))
           (values
             (let ((cl-concurrent-kit:*clock* clock))
               (multiple-value-list
                (redis-kit::%call-with-command-metrics
                 metrics
                 (lambda ()
                   (cl-boundary-kit:advance-fake-clock clock 10)
                   (values :left :right))))))
           (duration
             (metric-snapshot-by-name
              (redis-kit:redis-metrics-snapshot metrics)
              "redis_command_duration_seconds")))
      (expect values :to-equal '(:left :right))
      (expect (observability-kit:metric-sample-count
               (first (observability-kit:metric-snapshot-samples duration)))
              :to-be
              1)))

  (it "records successful command counters and duration samples"
    (let* ((registry (observability-kit:make-metric-registry))
           (connection (redis-kit:make-connection
                        :protocol :resp2
                        :handshake nil
                        :metric-registry registry
                        :network-boundary (make-test-boundary))))
      (unwind-protect
           (progn
             (expect (redis-kit:ping connection) :to-equal "PONG")
             (let* ((snapshots (redis-kit:connection-metrics-snapshot connection))
                    (commands (metric-snapshot-by-name
                               snapshots
                               "redis_commands_total"))
                    (duration (metric-snapshot-by-name
                               snapshots
                               "redis_command_duration_seconds")))
               (expect commands :to-be-truthy)
               (expect (observability-kit:metric-sample-value
                        (first (observability-kit:metric-snapshot-samples commands)))
                       :to-be
                       1)
               (expect duration :to-be-truthy)
               (expect (observability-kit:metric-sample-count
                        (first (observability-kit:metric-snapshot-samples duration)))
                       :to-be
                       1)))
        (redis-kit:close-connection connection))))

  (it "records command failures without hiding the Redis condition"
    (let* ((registry (observability-kit:make-metric-registry))
           (connection (redis-kit:make-connection
                        :protocol :resp2
                        :handshake nil
                        :metric-registry registry
                        :network-boundary (make-error-boundary))))
      (unwind-protect
           (progn
             (signals redis-kit:redis-server-error
               (redis-kit:ping connection))
             (let* ((snapshots (redis-kit:connection-metrics-snapshot connection))
                    (errors (metric-snapshot-by-name
                             snapshots
                             "redis_command_errors_total")))
               (expect errors :to-be-truthy)
               (expect (observability-kit:metric-sample-value
                        (first (observability-kit:metric-snapshot-samples errors)))
                       :to-be
                       1)))
        (redis-kit:close-connection connection)))))
