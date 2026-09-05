(require :asdf)

(defun script-directory ()
  (let ((source (or *load-truename* *compile-file-truename*)))
    (unless source
      (error "run-coverage.lisp must be loaded from a file"))
    (make-pathname :name nil :type nil :defaults source)))

(defun register-local-systems (root)
  (dolist (relative
           '("../cl-codec-kit/"
             "../cl-concurrent-kit/"
             "../cl-date-kit/"
             "../cl-boundary-kit/"
             "../cl-observability-kit/"
             "../cl-host-kit/"
             "../cl-weave/"))
    (let ((directory (merge-pathnames relative root)))
      (when (probe-file directory)
        (pushnew directory asdf:*central-registry* :test #'equal)))))

(let* ((root (script-directory))
       (source-directory (merge-pathnames #P"src/" root)))
  (load (merge-pathnames #P"coverage-paths.lisp" root))
  (register-local-systems root)
  (asdf:load-asd (merge-pathnames #P"cl-redis-kit.asd" root))
  (asdf:load-system "cl-redis-kit/test" :force t)
  (unless (uiop:symbol-call
           :redis-kit/test
           :run-tests
           :coverage t
           :coverage-include-pathnames
           (cl-redis-kit-core-source-pathnames source-directory)
           :coverage-exclude-pathnames nil
           :coverage-minimum-expression 100
           :coverage-minimum-branch 100
           :coverage-reset t)
    (uiop:quit 1)))

(uiop:quit 0)
