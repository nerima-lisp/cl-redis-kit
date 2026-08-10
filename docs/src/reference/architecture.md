# Architecture

## Data flow

~~~text
command arguments
       |
       v
  command specs  --->  command helpers
       |                     |
       v                     v
  RESP encoder  --->  connection execution
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
| Command specs/helpers | Declarative command metadata and generated convenience functions |
| Pool | Lazy bounded borrowing and return of connections |
| Metrics | Aggregate command counters, errors, and duration |
| Optional integrations | TLS and resilience specializations kept outside the core system |

## Dependency boundaries

The core ASDF system owns protocol, connection, commands, pools, and metrics. Its
declared dependencies include the boundary, codec, concurrency, date, and
observability libraries plus `usocket`.

`"cl-redis-kit/tls"` adds the `cl+ssl` transport. The core system provides
the TLS option boundary, while the optional system supplies the concrete client
stream implementation.

`"cl-redis-kit/resilience"` adds the `cl-resilience-kit` retry integration.
Applications choose whether a request is retry-safe; loading the optional system
does not turn retries on for every command.
