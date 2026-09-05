(defun set (connection key value &key nx xx get ex px exat pxat keepttl timeout
                                      retry-safe-p)
  (when (and nx xx)
    (error 'redis-client-error
           :message "SET cannot use NX and XX together."))
  (let ((options (list :ex ex :px px :exat exat :pxat pxat))
        (arguments (list key value))
        (tail-options nil))
    (%one-expiration options)
    (when nx (push "NX" tail-options))
    (when xx (push "XX" tail-options))
    (when get (push "GET" tail-options))
    (dolist (option '(:ex :px :exat :pxat))
      (let ((value (getf options option)))
        (when value
          (push (string-upcase (symbol-name option)) tail-options)
          (push value tail-options))))
    (when keepttl (push "KEEPTTL" tail-options))
    (%command-value connection "SET"
                    (append arguments (nreverse tail-options))
                    :decode :utf-8
                    :timeout timeout
                    :retry-safe-p retry-safe-p)))

(defun incr (connection key &rest arguments)
  (multiple-value-bind (values options)
      (%single-command-argument arguments "INCR")
    (%command-value connection (if values "INCRBY" "INCR")
                    (if values (list key (first values)) (list key))
                    :decode :utf-8
                    :timeout (getf options :timeout)
                    :retry-safe-p (getf options :retry-safe-p))))

(defun decr (connection key &rest arguments)
  (multiple-value-bind (values options)
      (%single-command-argument arguments "DECR")
    (%command-value connection (if values "DECRBY" "DECR")
                    (if values (list key (first values)) (list key))
                    :decode :utf-8
                    :timeout (getf options :timeout)
                    :retry-safe-p (getf options :retry-safe-p))))

(defun %expiration-command (connection command key duration options timeout
                                      retry-safe-p)
  (let ((arguments (list key duration))
        (tail-options nil))
    (when (and (getf options :nx) (getf options :xx))
      (error 'redis-client-error
             :message "An expiration cannot use NX and XX together."))
    (dolist (option '(:nx :xx :gt :lt))
      (when (getf options option)
        (push (string-upcase (symbol-name option)) tail-options)))
    (%command-value connection command
                    (append arguments (nreverse tail-options))
                    :decode :utf-8
                    :timeout timeout
                    :retry-safe-p retry-safe-p)))

(defun expire (connection key seconds &key nx xx gt lt timeout retry-safe-p)
  (%expiration-command connection "EXPIRE" key seconds
                       (list :nx nx :xx xx :gt gt :lt lt) timeout
                       retry-safe-p))

(defun pexpire (connection key milliseconds &key nx xx gt lt timeout retry-safe-p)
  (%expiration-command connection "PEXPIRE" key milliseconds
                       (list :nx nx :xx xx :gt gt :lt lt) timeout
                       retry-safe-p))
