(in-package #:asdf-user)

(defsystem "cl-redis-kit"
  :description "A binary-safe Redis RESP2/RESP3 client for Common Lisp."
  :author "takeokunn <barararaty@gmail.com>"
  :license "MIT"
  :version "2.0.0"
  :homepage "https://github.com/nerima-lisp/cl-redis-kit"
  :bug-tracker "https://github.com/nerima-lisp/cl-redis-kit/issues"
  :source-control (:git "https://github.com/nerima-lisp/cl-redis-kit.git")
  :depends-on ((:version "cl-boundary-kit" "2.3.0")
               (:version "cl-codec-kit" "0.5.0")
               (:version "cl-concurrent-kit" "0.6.1")
               (:version "cl-date-kit" "1.0.0")
               (:version "cl-observability-kit" "0.1.0")
               (:version "cl-weave" "1.3.0")
               "usocket")
  :pathname "src"
  :serial t
  :around-compile
  (lambda (thunk)
    (let ((*package* (or (find-package '#:redis-kit) *package*)))
      (funcall thunk)))
  :components ((:file "package")
               (:file "keyword-options")
               (:file "conditions")
               (:file "condition-report")
               (:file "protocol-model")
               (:file "protocol-values")
               (:file "protocol-reader")
               (:file "protocol-scalar-decoder")
               (:file "protocol-aggregate-decoder")
               (:file "protocol-api")
               (:file "protocol-encoder")
               (:file "metrics-api")
               (:file "metrics")
               (:file "tls-api")
               (:file "tls")
               (:file "connection-model-data")
               (:file "connection-model")
               (:file "execution-journal-api")
               (:file "execution-journal")
               (:file "connection-transport")
               (:file "connection-lifecycle")
               (:file "connection-policy-api")
               (:file "connection-policy")
               (:file "connection-pipeline")
               (:file "connection-scope-api")
               (:file "connection-scope")
               (:file "command-data-model")
               (:file "command-data-registration")
               (:file "command-data")
               (:file "command-spec")
               (:file "command-helpers")
               (:file "commands-connection")
               (:file "commands-key-value-declarations")
               (:file "commands-key-value")
               (:file "commands-collections-declarations")
               (:file "commands-collections")
               (:file "pool-model-data")
               (:file "pool-model")
               (:file "pool")
               (:file "pool-api"))
  :in-order-to ((test-op (test-op "cl-redis-kit/test"))))

(defsystem "cl-redis-kit/tls"
  :description "Optional cl+ssl transport integration for cl-redis-kit."
  :license "MIT"
  :version "2.0.0"
  :depends-on ("cl-redis-kit" "cl+ssl")
  :pathname "src"
  :components ((:file "tls-cl+ssl")))

(defsystem "cl-redis-kit/resilience"
  :description "Optional cl-resilience-kit integration for cl-redis-kit."
  :license "MIT"
  :version "2.0.0"
  :depends-on ("cl-redis-kit"
               (:version "cl-resilience-kit" "1.0.0"))
  :pathname "src"
  :components ((:file "connection-resilience")))

(defsystem "cl-redis-kit/test"
  :description "Tests for cl-redis-kit."
  :license "MIT"
  :version "2.0.0"
  :depends-on ("cl-redis-kit"
               (:version "cl-weave" "1.3.0"))
  :pathname "t"
  :serial t
  :components ((:file "package")
               (:file "protocol")
               (:file "protocol-edge")
               (:file "codec-edge")
               (:file "boundary")
               (:file "transport")
               (:file "lifecycle-edge")
               (:file "execution")
               (:file "command-spec")
               (:file "properties")
               (:file "metrics")
               (:file "commands")
               (:file "pool")
               (:file "pool-edge"))
  :perform (test-op (o c)
             (declare (ignore o c))
             (unless (uiop:symbol-call :redis-kit/test :run-tests)
               (error "cl-redis-kit tests failed"))))

(defsystem "cl-redis-kit/resilience/test"
  :description "Tests for the optional cl-resilience-kit integration."
  :license "MIT"
  :version "2.0.0"
  :depends-on ("cl-redis-kit/resilience"
               (:version "cl-weave" "1.3.0"))
  :pathname "t"
  :components ((:file "resilience"))
  :perform (test-op (o c)
             (declare (ignore o c))
             (unless (uiop:symbol-call :redis-kit/resilience-test :run-tests)
               (error "cl-redis-kit resilience tests failed"))))
