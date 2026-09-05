(defmacro with-command-metrics ((metrics-var metrics-form) &body body)
  "Run BODY and record one logical command in METRICS-FORM.

The macro preserves all values from BODY and records failures before
re-signalling the original condition."
  `(let ((,metrics-var ,metrics-form))
     (if ,metrics-var
         (%call-with-command-metrics
          ,metrics-var
          (lambda () (progn ,@body)))
         (progn ,@body))))
