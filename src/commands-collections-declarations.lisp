(define-redis-command hget "HGET"
    (key field &key (decode :utf-8) timeout (retry-safe-p t))
  :arguments (list key field)
  :decode decode
  :timeout timeout
  :retry-safe-p retry-safe-p)

(define-redis-command hset "HSET" (key &rest field-values)
  :arguments (cons key (%require-even-values field-values "HSET")))

(define-redis-command hdel "HDEL" (key &rest fields)
  :arguments (%require-key-values key fields "HDEL"))

(define-redis-command lpush "LPUSH" (key &rest values)
  :arguments (%require-key-values key values "LPUSH"))

(define-redis-command rpush "RPUSH" (key &rest values)
  :arguments (%require-key-values key values "RPUSH"))

(define-redis-command lrange "LRANGE"
    (key start stop &key (decode :utf-8) timeout (retry-safe-p t))
  :arguments (list key start stop)
  :decode decode
  :timeout timeout
  :retry-safe-p retry-safe-p)

(define-redis-command sadd "SADD" (key &rest members)
  :arguments (%require-key-values key members "SADD"))

(define-redis-command smembers "SMEMBERS"
    (key &key (decode :utf-8) timeout (retry-safe-p t))
  :arguments (list key)
  :decode decode
  :timeout timeout
  :retry-safe-p retry-safe-p)

(define-redis-command zadd "ZADD" (key &rest score-members)
  :arguments (cons key (%require-even-values score-members "ZADD")))

(define-redis-command zrange "ZRANGE"
    (key start stop &key with-scores (decode :utf-8)
                       timeout (retry-safe-p t))
  :arguments (append (list key start stop)
                     (when with-scores (list "WITHSCORES")))
  :decode decode
  :timeout timeout
  :retry-safe-p retry-safe-p)

(define-redis-command publish "PUBLISH"
    (channel message &key timeout retry-safe-p)
  :arguments (list channel message)
  :timeout timeout
  :retry-safe-p retry-safe-p)

(define-redis-command flushdb "FLUSHDB" (&key async timeout retry-safe-p)
  :arguments (when async (list "ASYNC"))
  :timeout timeout
  :retry-safe-p retry-safe-p)
