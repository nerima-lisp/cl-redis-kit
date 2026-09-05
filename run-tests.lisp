(require :asdf)

(defun script-directory ()
  (let ((source (or *load-truename* *compile-file-truename*)))
    (unless source
      (error "run-tests.lisp must be loaded from a file"))
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

(defun environment-true-p (name)
  (member (string-downcase (or (uiop:getenv name) ""))
          '("1" "true" "yes")
          :test #'string=))

(defun environment-value (name)
  (let ((value (uiop:getenv name)))
    (when (and value (plusp (length value)))
      value)))

(defun coverage-source-pathnames (source-directory)
  (let ((helper 'cl-redis-kit-core-source-pathnames))
    (unless (fboundp helper)
      (error "coverage-paths.lisp did not define ~S." helper))
    (funcall (symbol-function helper) source-directory)))

(let ((root (script-directory)))
  (when (environment-true-p "REDIS_KIT_COVERAGE")
    (load (merge-pathnames #P"coverage-paths.lisp" root))))

(let* ((root (script-directory))
       (coverage (not (null (environment-true-p "REDIS_KIT_COVERAGE"))))
       (source-directory (merge-pathnames #P"src/" root))
       (report-directory
         (let ((value (environment-value "REDIS_KIT_COVERAGE_REPORT")))
           (when value
             (uiop:ensure-directory-pathname (pathname value)))))
       (coverage-include-pathnames
         (and coverage
              (coverage-source-pathnames source-directory)))
       (coverage-exclude-pathnames nil))
  (register-local-systems root)
  (when coverage
    #+sbcl
    (progn
      (require :sb-cover)
      (let ((policy (find-symbol "STORE-COVERAGE-DATA" "SB-COVER")))
        (unless policy
          (error "SB-COVER compiler policy is not available."))
        (proclaim (list 'optimize (list policy 3)))))
    #-sbcl
    (error "REDIS_KIT_COVERAGE requires SBCL sb-cover."))
  (load (merge-pathnames #P"cl-redis-kit.asd" root))
  (if coverage
      (progn
        (asdf:operate (quote asdf:load-op) "cl-redis-kit" :force t)
        (asdf:operate (quote asdf:load-op) "cl-redis-kit/test" :force t))
      (asdf:load-system "cl-redis-kit/test"))
  (when report-directory
    (ensure-directories-exist
     (uiop:ensure-directory-pathname (pathname report-directory))))
  (unless (uiop:symbol-call
           :redis-kit/test :run-tests
           :coverage coverage
           :coverage-output (environment-value "REDIS_KIT_COVERAGE_OUTPUT")
           :coverage-report-directory report-directory
           :coverage-include-pathnames coverage-include-pathnames
           :coverage-exclude-pathnames coverage-exclude-pathnames
           :coverage-minimum-expression (and coverage 100)
           :coverage-minimum-branch (and coverage 100))
    (uiop:quit 1))
  (uiop:quit 0))
