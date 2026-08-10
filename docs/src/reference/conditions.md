# Conditions

## Hierarchy

~~~text
error
+-- redis-error
    |-- redis-client-error
    |   |-- redis-protocol-error
    |   |-- redis-connection-error
    |       +-- redis-timeout-error
    +-- redis-server-error
~~~

All project conditions inherit from `redis-error` and expose a message and
optional cause. Protocol errors add a parser position; server errors add the
server error code and original reply.

## Exported readers

| Reader | Applies to | Meaning |
| --- | --- | --- |
| `redis-error-message` | `redis-error` | Human-readable message |
| `redis-error-cause` | `redis-error` | Underlying condition, when present |
| `redis-error-position` | `redis-protocol-error` | Position at which parsing failed |
| `redis-error-code` | `redis-server-error` | Redis server error code |
| `redis-error-reply` | `redis-server-error` | Original error reply |

Use `typep` with `redis-error` or a more specific condition type when handling
failures.
Timeouts are connection errors, while server errors remain separate from client
and transport failures.
