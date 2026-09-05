# Architecture

## Data flow

~~~text
command arguments
       |
       v
  command specs  --->  command helpers
       |                     |
       v                     v
  RESP encoder  --->  execution policy
                              |
  pipelines --------------> connection scope
                              |
                              v
                       network boundary
                              |
                              v
                       RESP decoder
                              |
                              v
                        typed replies
~~~

## Source layers

| Layer | Responsibility |
| --- | --- |
| Protocol model/API | RESP values, limits, encoding, decoding, and frame errors |
| Connection model/lifecycle | Configuration, handshake, authentication, database selection, and close semantics |
| Connection transport/execution | Network I/O, deadlines, retries, pipelines, and push replies |
| Command specs/helpers | Declarative command metadata and command helper functions |
| Pool | Lazy bounded borrowing and return of connections |
| Metrics | Aggregate command counters, errors, and duration |
| Optional integrations | TLS and resilience specializations kept outside the core system |

## Dependency boundaries

The core ASDF system owns protocol, connection, commands, pools, metrics, and the
execution journal. Its declared dependencies include the boundary, codec,
concurrency, date, observability, and `cl-weave` libraries plus `usocket`.

`cl-weave` is used directly at the actual command-attempt boundaries. Applications
opt in with `cl-weave:with-execution-journal`; recorded frames contain the command
name, argument count, reply shape, or error type, but never command payloads. With
no active journal, the instrumentation is a no-op.

`"cl-redis-kit/tls"` adds the `cl+ssl` transport. The core system provides
the TLS option boundary, while the optional system supplies the concrete client
stream implementation.

`"cl-redis-kit/resilience"` adds the `cl-resilience-kit` retry integration.
Applications choose whether a request is retry-safe; loading the optional system
does not turn retries on for every command.
