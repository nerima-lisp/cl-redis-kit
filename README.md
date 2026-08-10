# cl-redis-kit

A binary-safe Common Lisp Redis client with RESP2/RESP3 support, explicit connection
lifecycle, bounded pools, pipelines, push replies, and optional TLS/resilience systems.
See the [documentation](docs/src/index.md) for the complete guide and API reference.

## Quick Start

~~~lisp
(asdf:load-system "cl-redis-kit")

(redis-kit:with-connection (connection :host "127.0.0.1")
  (redis-kit:execute connection "SET" "key" "value")
  (redis-kit:execute connection "GET" "key"))
~~~

`execute` returns the decoded value of a reply. Use `execute-reply` when the
typed RESP reply, including attributes, is needed.

## Install

Load the ASDF system from a Common Lisp environment with the project available in
`CL_SOURCE_REGISTRY`:

~~~lisp
(asdf:load-system "cl-redis-kit")
~~~

For the reproducible development environment, run `nix develop` from the project
root.

## Documentation

- [Getting started](docs/src/getting-started.md)
- [Core concepts](docs/src/guide/core-concepts.md)
- [Recipes](docs/src/guide/recipes.md)
- [API reference](docs/src/reference/api.md)
- [Architecture](docs/src/reference/architecture.md)
- [Conditions](docs/src/reference/conditions.md)
- [Compatibility](docs/src/reference/compatibility.md)
- [Development](docs/src/project/development.md)

## Development

~~~sh
nix develop
nix run .#test
nix flake check
nix build .#coverage
nix build .#tls
nix fmt
~~~

The flake exposes the test runner, coverage report, TLS package, formatter, and
checks. The [development guide](docs/src/project/development.md) also documents
direct test execution and strict documentation builds.

## Contributing

Keep the README, `docs/src` pages, ASDF systems, and exported API synchronized.
Run the relevant Nix checks before submitting a change.

## Support

For a reproducible bug report, include the Lisp implementation, Redis version,
minimal reproduction, and the command or test that demonstrates the problem.

## License

MIT. See [LICENSE](LICENSE).
