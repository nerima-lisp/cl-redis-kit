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

(defun environment-percentage (name)
  (let ((value (environment-value name)))
    (when value
      (let ((percentage (parse-integer value :junk-allowed nil)))
        (unless (<= 0 percentage 100)
          (error "~A must be an integer from 0 through 100, got ~S."
                 name value))
        percentage))))

(let* ((root (script-directory))
       (coverage (not (null (environment-true-p "REDIS_KIT_COVERAGE"))))
       (report-directory
         (let ((value (environment-value "REDIS_KIT_COVERAGE_REPORT")))
           (when value
             (uiop:ensure-directory-pathname (pathname value)))))
       (coverage-include-pathnames
         (and coverage
              (list (merge-pathnames #P"src/" root)))))
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
  (asdf:load-asd (merge-pathnames #P"cl-redis-kit.asd" root))
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
           :coverage-minimum-expression
           (and coverage
                (environment-percentage
                 "REDIS_KIT_COVERAGE_MINIMUM_EXPRESSION"))
           :coverage-minimum-branch
           (and coverage
                (environment-percentage
                 "REDIS_KIT_COVERAGE_MINIMUM_BRANCH")))
    (uiop:quit 1))
  (uiop:quit 0))
