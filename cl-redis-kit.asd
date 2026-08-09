(in-package #:asdf-user)

(defsystem "cl-redis-kit"
  :description "A binary-safe Redis RESP2/RESP3 client for Common Lisp."
  :author "takeokunn <barararaty@gmail.com>"
  :license "MIT"
  :version "2.0.0"
  :homepage "https://github.com/nerima-lisp/cl-redis-kit"
  :bug-tracker "https://github.com/nerima-lisp/cl-redis-kit/issues"
  :source-control (:git "https://github.com/nerima-lisp/cl-redis-kit.git")
  :depends-on ("cl-boundary-kit"
               "cl-codec-kit"
               "cl-concurrent-kit"
               "cl-date-kit"
               "cl-observability-kit"
               "cl+ssl"
               "usocket")
  :pathname "src"
  :serial t
  :components ((:file "package")
               (:file "conditions")
               (:file "protocol-model")
               (:file "protocol-values")
               (:file "protocol-reader")
               (:file "protocol-scalar-decoder")
               (:file "protocol-aggregate-decoder")
               (:file "protocol-api")
               (:file "protocol-encoder")
               (:file "metrics")
               (:file "tls")
               (:file "connection-model")
               (:file "connection-transport")
               (:file "connection-lifecycle")
               (:file "connection-execution")
               (:file "command-data")
               (:file "command-spec")
               (:file "command-helpers")
               (:file "commands-connection")
               (:file "commands-key-value")
               (:file "commands-collections")
               (:file "pool"))
  :in-order-to ((test-op (test-op "cl-redis-kit/test"))))

(defsystem "cl-redis-kit/resilience"
  :description "Optional cl-resilience-kit integration for cl-redis-kit."
  :license "MIT"
  :version "2.0.0"
  :depends-on ("cl-redis-kit" "cl-resilience-kit")
  :pathname "src"
  :components ((:file "connection-resilience")))

(defsystem "cl-redis-kit/test"
  :description "Tests for cl-redis-kit."
  :license "MIT"
  :version "2.0.0"
  :depends-on ("cl-redis-kit" "cl-weave")
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
               (:file "weave")
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
  :depends-on ("cl-redis-kit/resilience" "cl-weave")
  :pathname "t"
  :components ((:file "resilience"))
  :perform (test-op (o c)
             (declare (ignore o c))
             (unless (uiop:symbol-call :redis-kit/resilience-test :run-tests)
               (error "cl-redis-kit resilience tests failed"))))
