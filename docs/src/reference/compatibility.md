# Compatibility

## Version boundary

Version 2 is a clean break from the earlier API. Applications should use the
current package exports and the ASDF systems documented in this site rather than
assuming compatibility with pre-2.x names or lifecycle behavior.

## Redis protocol

The client negotiates RESP3 by default and falls back to RESP2 when the server
does not support `HELLO`. The protocol parser and encoder preserve binary
data; text decoding is an execution choice.

## Optional dependencies

The core system remains independent of `cl+ssl` and
`cl-resilience-kit`. Load `cl-redis-kit/tls` for TLS transport and
`"cl-redis-kit/resilience"` for resilience-backed retry calls.

## Deliberate removals

The pre-2.x `pool-with-connection` alias is not exported. Use
`call-with-pool-connection` or `with-pool`; keeping one borrowing primitive
avoids two APIs with identical ownership semantics.

## Retry semantics

Retries are not a blanket guarantee. A retry policy must be configured, and a
request must be safe to repeat. Low-level execution accepts `:retry-safe-p`;
command helpers can provide command-specific safety metadata. Applications
should treat writes as non-retryable unless their own semantics make repetition
safe.

## Lifecycle

Connections are lazy, but opening performs negotiation and configured setup.
`with-connection` and `with-pool` delimit ownership and cleanup.
Closing is terminal for a connection object, and closing a pool prevents new
borrows.
