(defmacro with-connection ((variable &rest initargs) &body body)
  `(call-with-connection
    (make-connection ,@initargs)
    (lambda (,variable) ,@body)))
