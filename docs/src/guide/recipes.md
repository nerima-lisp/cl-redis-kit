# Recipes

## Pipeline commands

Pass command argument lists to `pipeline`. Replies remain in command order:

~~~lisp
(redis-kit:pipeline
 connection
 '(("SET" "a" "1")
   ("GET" "a")
   ("DEL" "a")))
~~~

`pipeline` and `pipeline-replies` both return typed replies, including
attributes. Pipelines are not atomic transactions.

## Raw bytes

Keep a bulk-string payload as octets by selecting the raw decoder:

~~~lisp
(let ((value (redis-kit:execute connection
                                "GET"
                                "binary-key"
                                :decode :raw)))
  (declare (type (vector (unsigned-byte 8)) value))
  value)
~~~

This is useful for serialized values and data that is not valid text.

## Reusing connections with a pool

~~~lisp
(let ((pool (redis-kit:make-pool :max-size 8)))
  (unwind-protect
       (redis-kit:with-pool (connection pool)
         (redis-kit:execute connection "PING"))
    (redis-kit:close-pool pool)))
~~~

Use `:max-wait` on `make-pool` when acquisition should fail after a
bounded wait.

## TLS

Load the optional TLS system before creating a TLS connection:

~~~lisp
(asdf:load-system "cl-redis-kit/tls")
(redis-kit:with-connection (connection
                             :host "127.0.0.1"
                             :port 6379
                             :tls '(:verify :required))
  (redis-kit:execute connection "PING"))
~~~

The core system does not load `cl+ssl`. Certificate, key, password, and
verification options are accepted by the TLS transport.

## Push replies

Use a push handler for immediate processing, or inspect accumulated pushes:

~~~lisp
(redis-kit:drain-pushes connection)
~~~

Push replies are separate from the ordinary result returned by
`execute` or `pipeline`.
