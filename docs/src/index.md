# cl-redis-kit

`cl-redis-kit` is a binary-safe Common Lisp Redis client. It supports RESP2 and
RESP3, typed replies, explicit connection lifecycle, pipelines, push replies,
bounded pools, and optional TLS and resilience integrations.

## Start here

- [Getting started](getting-started.md) loads the system and opens a connection.
- [Core concepts](guide/core-concepts.md) explains replies, lifecycle, retries,
  pools, and observability.
- [Recipes](guide/recipes.md) collects common execution patterns.

## Reference

- [API](reference/api.md) lists ASDF systems and exported entry points.
- [Architecture](reference/architecture.md) describes the source-layer boundaries.
- [Conditions](reference/conditions.md) describes the exported condition hierarchy.
- [Compatibility](reference/compatibility.md) records the 2.x behavior boundary.

For local checks and documentation builds, see [Development](project/development.md).
