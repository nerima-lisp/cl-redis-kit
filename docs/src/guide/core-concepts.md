# Core concepts

## Typed replies

`execute-reply` returns a `redis-reply` object with a type, value, and
optional attributes. The protocol helpers expose the object directly:

- `redis-reply-type` identifies the RESP type.
- `redis-reply-value` returns the decoded or raw value.
- `redis-reply-attributes` preserves RESP3 attributes.
- `reply-error-p` and `null-reply-p` classify common replies.

`execute` applies `reply-value` and is convenient for ordinary command
results. The lower-level `decode-reply` API returns the decoded reply and
the first unconsumed position; `read-reply` returns only the decoded reply.

## Connection lifecycle

`make-connection` creates a lazy connection object. `open-connection`
performs the handshake and transport setup; `close-connection` releases it.
The default handshake negotiates RESP3 and falls back to RESP2 when the server
does not support `HELLO`. Authentication and database selection are part of
the lifecycle when configured.

`with-connection` is the scoped form for a single owner. A closed connection
cannot be reopened; create a new connection when a fresh lifecycle is needed.

## Timeouts and retries

Connection setup, reads, and command execution have explicit timeout controls.
`:timeout` on `execute` and pipeline calls overrides the connection
default for that operation.

Retrying is policy-driven and must account for whether a command may have been
partially written. The low-level execution APIs expose `:retry-safe-p`;
command helpers can carry command-specific safety metadata.
Treat writes as non-retryable unless their application-level semantics make a
retry safe.

## Pipelines and push replies

`pipeline-replies` writes a non-empty sequence of commands and returns typed
replies in order. `pipeline` is a convenience counterpart with the same reply
behavior. A pipeline is not a transaction: commands are sent together, but
Redis applies its normal command semantics.

RESP3 push replies are collected independently of ordinary command results.
`drain-pushes` returns them in arrival order and clears the pending queue;
the configured push handler can process them as they arrive.

## Pools

`make-pool` creates a lazy, bounded pool. The default maximum size is eight.
`:max-wait nil` permits an unbounded wait for an available connection;
otherwise acquisition observes the configured non-negative wait limit.

`with-pool` borrows and returns a connection around a body.
`pool-execute` borrows a connection for one `execute` call. Closing the
pool closes idle connections and prevents further acquisition.

## Metrics

`make-redis-metrics` creates the project's aggregate metrics object and can
use a supplied observability registry. The standard instruments include command
count, command errors, and command duration. Use
`redis-metrics-snapshot` to read the current aggregate view.
