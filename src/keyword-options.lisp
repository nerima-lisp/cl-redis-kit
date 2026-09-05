(defun %keyword-supplied-p (arguments keyword)
  (loop for tail on arguments by #'cddr
        thereis (eq (car tail) keyword)))
