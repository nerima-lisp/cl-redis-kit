(defun %record-journal-frame-safely (kind &rest arguments)
  (block record-journal-frame
    (handler-bind
        ((error (lambda (condition)
                  (declare (ignore condition))
                  (return-from record-journal-frame))))
      (apply #'cl-weave:record-journal-frame kind arguments))))

(defun %journal-command-start (command argument-count)
  (%record-journal-frame-safely
   :redis-command
   :form command
   :actual (list :argument-count argument-count)
   :pass t))

(defun %journal-command-result (command result)
  (%record-journal-frame-safely
   :redis-result
   :form command
   :actual
   (cond
     ((redis-reply-p result)
      (list :reply-type (redis-reply-type result)))
     ((listp result)
      (list :reply-count (length result)))
     (t
      (list :result-type (type-of result))))
   :pass t))

(defun %journal-command-error (command condition)
  (%record-journal-frame-safely
   :redis-error
   :form command
   :actual (type-of condition)
   :pass nil))
