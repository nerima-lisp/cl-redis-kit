; paredit:ignore-file leftover-inspect-call -- CL-WEAVE's DESCRIBE is the BDD test DSL, not a debugger inspection call.
; paredit:ignore-file eval-of-non-constant -- REDIS-KIT:EVAL emits Redis's EVAL command; it is not Common Lisp EVAL.
(in-package #:redis-kit/test)

(defun command-integer-reply ()
  (decode-test-reply (test-octets 58 49 13 10)))

(defun command-array-reply ()
  (decode-test-reply
   (test-octets
    42 50 13 10
    36 49 13 10 97 13 10
    36 49 13 10 98 13 10)))

(defun command-reply-for (command)
  (cond
    ((string= command "PING") (test-simple-reply "PONG"))
    ((member command (list "GET" "HGET") :test (function string=))
     (test-bulk-reply "fixture"))
    ((member command (list "HELLO" "LRANGE" "SMEMBERS" "ZRANGE")
             :test (function string=))
     (command-array-reply))
    ((member command (list "DEL" "EXISTS" "INCR" "DECR" "INCRBY" "DECRBY" "EXPIRE"
                           "PEXPIRE" "TTL" "PTTL" "HSET" "HDEL" "LPUSH"
                           "RPUSH" "SADD" "ZADD" "PUBLISH" "EVAL")
             :test (function string=))
     (command-integer-reply))
    (t (test-simple-reply "OK"))))

(defun make-command-boundary (record-command)
  (cl-boundary-kit:make-network-boundary
   :request-fn
   (lambda (request &key timeout)
     (declare (ignore timeout))
     (multiple-value-bind (reply next)
         (redis-kit:decode-reply (getf request :bytes))
       (declare (ignore next))
       (let* ((command (redis-kit:reply-value reply))
              (name (first command))
              (response (command-reply-for name)))
         (funcall record-command command)
         (if (= (getf request :replies) 1)
             response
             (loop repeat (getf request :replies) collect response)))))))

(describe
    "Redis command API"
  (it "executes every public command through the shared boundary path"
    (let ((seen nil)
          (connection nil))
      (setf connection
            (redis-kit:make-connection
             :protocol :resp2
             :handshake nil
             :network-boundary (make-command-boundary (lambda (command) (push command seen)))))
      (unwind-protect
           (progn
             (expect (redis-kit:auth connection "password")
                     :to-equal "OK")
             (expect (redis-kit:auth connection "password"
                                     :username "user"
                                     :timeout 1)
                     :to-equal "OK")
             (expect (redis-kit:select connection 2) :to-equal "OK")
             (expect (redis-kit:hello connection 3) :to-equal '("a" "b"))
             (expect (redis-kit:ping connection "hello" :timeout 1)
                     :to-equal "PONG")
             (expect (redis-kit:get connection "key" :decode nil)
                     :to-equalp
                     (test-octets 102 105 120 116 117 114 101))
             (expect (redis-kit:set connection "key" "value"
                     :nx t
                                     :ex 10
                                     :timeout 1
                                     :retry-safe-p t)
                     :to-equal "OK")
             (expect (redis-kit:set connection "key" "value"
                                     :xx t
                                     :get t
                                     :keepttl t)
                     :to-equal "OK")
             (expect (redis-kit:del connection "key") :to-be 1)
             (expect (redis-kit:exists connection "key") :to-be 1)
             (expect (redis-kit:incr connection "counter") :to-be 1)
             (expect (redis-kit:incr connection "counter" 2) :to-be 1)
             (expect (redis-kit:decr connection "counter") :to-be 1)
             (expect (redis-kit:decr connection "counter" 2) :to-be 1)
             (expect (redis-kit:expire connection "key" 10 :nx t)
                     :to-be 1)
             (expect (redis-kit:pexpire connection "key" 10 :lt t)
                     :to-be 1)
             (expect (redis-kit:ttl connection "key") :to-be 1)
             (expect (redis-kit:pttl connection "key") :to-be 1)
             (expect (redis-kit:hget connection "hash" "field")
                     :to-equal "fixture")
             (expect (redis-kit:hset connection "hash" "field" "value")
                     :to-be 1)
             (expect (redis-kit:hdel connection "hash" "field") :to-be 1)
             (expect (redis-kit:lpush connection "list" "one") :to-be 1)
             (expect (redis-kit:rpush connection "list" "one") :to-be 1)
             (expect (redis-kit:lrange connection "list" 0 -1)
                     :to-equal '("a" "b"))
             (expect (redis-kit:sadd connection "set" "member") :to-be 1)
             (expect (redis-kit:smembers connection "set")
                     :to-equal '("a" "b"))
             (expect (redis-kit:zadd connection "scores" 1 "member")
                     :to-be 1)
             (expect (redis-kit:zrange connection "scores" 0 -1
                                       :with-scores t)
                     :to-equal '("a" "b"))
             (expect (redis-kit:publish connection "channel" "message")
                     :to-be 1)
             (expect (redis-kit:flushdb connection :async t) :to-equal "OK")
             (expect (redis-kit:eval connection "return 1" '("key") "arg"
                                     :decode :utf-8)
                     :to-be 1)
             (expect (redis-kit:quit connection) :to-equal "OK")
             (expect (mapcar (function first) (nreverse seen))
                     :to-equal
                     '("AUTH" "AUTH" "SELECT" "HELLO" "PING" "GET" "SET" "SET"
                       "DEL" "EXISTS" "INCR" "INCRBY" "DECR" "DECRBY"
                       "EXPIRE" "PEXPIRE"
                       "TTL" "PTTL" "HGET" "HSET" "HDEL" "LPUSH" "RPUSH"
                       "LRANGE" "SADD" "SMEMBERS" "ZADD" "ZRANGE" "PUBLISH"
                       "FLUSHDB" "EVAL" "QUIT")))
        (redis-kit:close-connection connection))))

  (it "rejects invalid command specifications before network I/O"
    (let ((connection (redis-kit:make-connection
                       :protocol :resp2
                       :handshake nil
                       :network-boundary (make-test-boundary))))
      (unwind-protect
           (progn
             (signals redis-kit:redis-client-error
               (redis-kit:set connection "key" "value" :nx t :xx t))
             (signals redis-kit:redis-client-error
               (redis-kit:set connection "key" "value" :ex 1 :px 1000))
             (signals redis-kit:redis-client-error
               (redis-kit:expire connection "key" 10 :nx t :xx t))
             (signals redis-kit:redis-client-error
               (redis-kit:hset connection "hash" "field"))
             (signals redis-kit:redis-client-error
               (redis-kit:zadd connection "scores" 1))
             (signals redis-kit:redis-client-error
               (redis-kit:del connection))
             (signals redis-kit:redis-client-error
               (redis-kit:ping connection "one" "two"))
             (signals redis-kit:redis-client-error
               (redis-kit:eval connection "return 1" "not-a-list"))
             (signals redis-kit:redis-client-error
               (redis-kit:execute connection "PING" :timeout)))
        (redis-kit:close-connection connection)))))
