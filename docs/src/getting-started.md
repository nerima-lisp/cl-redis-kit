# Getting started

## Requirements

The core system is an ASDF system and depends on the Common Lisp libraries declared
by the project. A running Redis server is required for connection examples.

Load the system from a Lisp image:

~~~lisp
(asdf:load-system "cl-redis-kit")
~~~

The core package is `redis-kit`. The shortest connection example is:

~~~lisp
(redis-kit:with-connection (connection :host "127.0.0.1")
  (redis-kit:execute connection "SET" "greeting" "hello")
  (redis-kit:execute connection "GET" "greeting"))
~~~

`with-connection` opens the connection for the body and closes it afterward.
`execute` returns the value converted from the server reply. Use
`execute-reply` when callers need the typed `redis-reply` object instead.

## Connection defaults

`make-connection` defaults to loopback host `127.0.0.1`, port `6379`,
RESP3 negotiation, a five-second operation timeout, and an automatic handshake.
The connection can also be configured with separate connect and read timeouts,
authentication, a database, a retry policy, a push handler, a metrics registry,
or a custom network boundary.

## Preserving bytes

Use `:decode :raw` when a bulk-string value must remain an octet vector:

~~~lisp
(redis-kit:execute connection "GET" "binary-key" :decode :raw)
~~~

`:decode nil` also avoids text decoding. The default `:decode :utf-8`
converts bulk strings to text.

## Optional integrations

TLS is isolated from the core system:

~~~lisp
(asdf:load-system "cl-redis-kit/tls")

(redis-kit:with-connection (connection :host "127.0.0.1" :tls t)
  (redis-kit:execute connection "PING"))
~~~

The TLS system supplies the `cl+ssl` transport. Load
`"cl-redis-kit/resilience"` when a retry policy is backed by
`cl-resilience-kit`.
