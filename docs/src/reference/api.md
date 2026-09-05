# API reference

## ASDF systems

| System | Purpose |
| --- | --- |
| `cl-redis-kit` | Core protocol, connection, command, pool, and metrics APIs |
| `cl-redis-kit/tls` | Optional `cl+ssl` transport |
| `cl-redis-kit/resilience` | Optional `cl-resilience-kit` retry integration |
| `cl-redis-kit/test` | Main test system |
| `cl-redis-kit/resilience/test` | Resilience integration tests |

The core system does not require the optional TLS or resilience systems. It
includes the opt-in `cl-weave` execution journal; wrap application operations in
`cl-weave:with-execution-journal` to collect payload-free command, result, and
error frames.

## Protocol

The protocol surface includes:

- `redis-reply`, `redis-reply-p`, `redis-reply-type`,
  `redis-reply-value`, and `redis-reply-attributes`
- `decode-reply` and `read-reply`
- `encode-command` and `encode-commands`
- `reply-value`, `reply-error-p`, and `null-reply-p`

The parser exposes configurable limits for line length, bulk length, array
length, nesting depth, and complete frame size. The default limits are:

| Limit | Default |
| --- | ---: |
| Line length | 16 KiB |
| Bulk string | 512 MiB |
| Array length | 1,000,000 elements |
| Nesting depth | 128 |
| Frame size | 512 MiB |

## Connections and execution

The main connection entry points are:

`make-connection`, `open-connection`, `close-connection`,
`connection-open-p`, `connection-state`, and
`connection-network-boundary`.

Use `execute-reply` for typed replies and `execute` for converted values.
`pipeline-replies` and `pipeline` execute command sequences.
`drain-pushes` retrieves pending RESP3 push replies.
`call-with-connection` and `with-connection` provide scoped execution.

## Commands

The command-spec API provides `define-redis-command`,
`redis-command-spec`, and specification accessors.

The exported generated commands cover:

- Connection: `auth`, `select`, `hello`, `ping`, `quit`
- Strings and counters: `get`, `set`, `del`, `exists`,
  `incr`, `decr`
- Expiration: `expire`, `pexpire`, `ttl`, `pttl`
- Hashes and lists: `hget`, `hset`, `hdel`, `lpush`,
  `rpush`, `lrange`
- Sets and sorted sets: `sadd`, `smembers`, `zadd`, `zrange`
- Pub/sub and server: `publish`, `flushdb`
- Scripting: `eval`

## Pools

`make-pool`, `close-pool`, `pool-closed-p`, `pool-size`,
`pool-idle-count`, `pool-max-size`, `pool-max-wait`,
`call-with-pool-connection`,
`pool-execute`, and `with-pool` make up the pool API.

## Metrics

`make-redis-metrics` creates a metrics object;
`redis-metrics-registry` returns its registry and
`redis-metrics-snapshot` returns aggregate values.
