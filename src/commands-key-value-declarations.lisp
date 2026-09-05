(define-redis-command get "GET"
    (key &key (decode :utf-8) timeout (retry-safe-p t))
  :arguments (list key)
  :decode decode
  :timeout timeout
  :retry-safe-p retry-safe-p)

(define-redis-command del "DEL" (&rest keys)
  :arguments (%require-values keys "DEL"))

(define-redis-command exists "EXISTS" (&rest keys)
  :arguments (%require-values keys "EXISTS")
  :retry-safe-p t)

(define-redis-command ttl "TTL" (key &key timeout (retry-safe-p t))
  :arguments (list key)
  :timeout timeout
  :retry-safe-p retry-safe-p)

(define-redis-command pttl "PTTL" (key &key timeout (retry-safe-p t))
  :arguments (list key)
  :timeout timeout
  :retry-safe-p retry-safe-p)
