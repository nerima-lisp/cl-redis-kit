(defmacro with-pool ((variable pool &key (timeout nil timeoutp)) &body body)
  "Borrow VARIABLE from POOL for BODY and return it afterward."
  (if timeoutp
      `(call-with-pool-connection ,pool
                                  (lambda (,variable) ,@body)
                                  :timeout ,timeout)
      `(call-with-pool-connection ,pool
                                  (lambda (,variable) ,@body))))
