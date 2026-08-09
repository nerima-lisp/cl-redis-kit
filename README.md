# cl-redis-kit

`cl-redis-kit` is a binary-safe Redis RESP2/RESP3 client for Common Lisp. The
2.x API is intentionally a clean break from the previous API; applications
should target the interfaces documented here rather than rely on legacy
adapters.

## Highlights

- RESP2 and RESP3 decoding, including binary bulk values and push replies.
- Macro-defined command specifications for the regular command surface.
- Explicit CPS-style connection and pool boundaries for testable I/O.
- `cl-boundary-kit` for the network boundary, `cl-codec-kit` for octet/string
  conversion, `cl-concurrent-kit` for locks and timeouts, `cl-date-kit` for
  durations, and `cl-observability-kit` for metrics.
- `cl-weave` tests with property and fuzz cases, plus SBCL coverage reports.

## Quick start

Load the ASDF system and use the package-qualified API:

```lisp
(asdf:load-system "cl-redis-kit")

(redis-kit:with-connection (connection :host "127.0.0.1" :port 6379)
  (redis-kit:set connection "greeting" "hello")
  (redis-kit:get connection "greeting"))
```

`make-connection` also accepts `:protocol :resp2` or `:protocol :resp3`,
authentication and database options, TLS options, an optional retry policy,
an injected `cl-boundary-kit` network boundary, and an observability metric
registry. Retry-safe execution is opt-in with `:retry-safe-p t`.
Use `redis-kit:with-pool` when several operations should share a bounded pool:

```lisp
(let ((pool (redis-kit:make-pool :host "127.0.0.1"
                                :port 6379
                                :max-size 8)))
  (unwind-protect
       (redis-kit:with-pool (connection pool)
         (redis-kit:ping connection))
    (redis-kit:close-pool pool)))
```

## Systems and dependencies

The main ASDF system depends on these `nerima-lisp` packages:

- `cl-boundary-kit`
- `cl-codec-kit`
- `cl-concurrent-kit`
- `cl-date-kit`
- `cl-observability-kit`

It also uses `usocket` for the default transport. The test system adds
`cl-weave`, and TLS uses the direct public API of `cl+ssl`. The Nix flake pins
the reviewed package sources and provides the package, development shell,
tests, coverage output, and a `paredit-cli` structural lint check.

The client calls the nerima-lisp packages above through their public APIs
directly; it does not add local adapters around the boundary, codec,
concurrency, date, observability, or test abstractions. `cl-host-kit` remains a
transitive dependency of `cl-boundary-kit` because this client does not use its
filesystem or process APIs directly.

The optional `cl-redis-kit/resilience` ASDF system integrates directly with
the public `cl-resilience-kit:call-with-resilience` API. Load that system only
when `cl-resilience-kit` is available separately:

```lisp
(asdf:load-system "cl-redis-kit/resilience")
```

Without the optional system, a configured retry policy remains inert for
ordinary commands, while `:retry-safe-p t` signals a client error instead of
silently executing outside the requested policy.

### ASDF systems

The repository defines four ASDF systems:

- `cl-redis-kit` is the production client.
- `cl-redis-kit/test` contains the standard protocol, transport, lifecycle,
  command, pool, metrics, and property/fuzz tests. It is the system loaded by
  `run-tests.lisp` and by the main system's `test-op`.
- `cl-redis-kit/resilience` provides the optional direct integration with
  `cl-resilience-kit`.
- `cl-redis-kit/resilience/test` tests that optional integration separately,
  so installations without `cl-resilience-kit` can still use and test the
  main client.

Load the resilience test system only in an environment that provides
`cl-resilience-kit`:

```lisp
(asdf:test-system "cl-redis-kit/resilience/test")
```

## Development

With Nix installed, enter the reproducible development environment:

```sh
nix develop
nix flake check
```

To run the test runner directly from the Nix environment, make the local
dependency checkouts and the Nix-provided ASDF systems visible:

```sh
project_root="$(pwd)"
export CL_SOURCE_REGISTRY="${project_root}/../cl-codec-kit/:${project_root}/../cl-concurrent-kit/:${project_root}/../cl-date-kit/:${project_root}/../cl-boundary-kit/:${project_root}/../cl-observability-kit/:${project_root}/../cl-host-kit/:${project_root}/../cl-weave/:"
for package in usocket split-sequence cl_plus_ssl alexandria babel bordeaux-threads cffi flexi-streams global-vars trivial-features trivial-garbage trivial-gray-streams; do
  CL_SOURCE_REGISTRY="${CL_SOURCE_REGISTRY}$(nix eval --raw "nixpkgs#sbclPackages.${package}.outPath")/:"
done
sbcl --noinform --non-interactive --load run-tests.lisp
```

The suite uses `cl-weave` and fails when no tests are selected. It covers
protocol behavior, injected network boundaries, command encoding, pool
lifecycles, metrics, and property/fuzz cases.

For an SBCL coverage report, set the report variable to a directory pathname
(including its trailing slash):

```sh
coverage_dir="$(mktemp -d)/"
project_root="$(pwd)"
export CL_SOURCE_REGISTRY="${project_root}/../cl-codec-kit/:${project_root}/../cl-concurrent-kit/:${project_root}/../cl-date-kit/:${project_root}/../cl-boundary-kit/:${project_root}/../cl-observability-kit/:${project_root}/../cl-host-kit/:${project_root}/../cl-weave/:"
for package in usocket split-sequence cl_plus_ssl alexandria babel bordeaux-threads cffi flexi-streams global-vars trivial-features trivial-garbage trivial-gray-streams; do
  CL_SOURCE_REGISTRY="${CL_SOURCE_REGISTRY}$(nix eval --raw "nixpkgs#sbclPackages.${package}.outPath")/:"
done
REDIS_KIT_COVERAGE=true \
REDIS_KIT_COVERAGE_REPORT="$coverage_dir" \
REDIS_KIT_COVERAGE_OUTPUT="${coverage_dir}coverage.data" \
  sbcl --noinform --non-interactive --load run-tests.lisp
```

Coverage is an explicit 100% improvement target. The generated report is the
acceptance artifact; it is not committed to the repository. To make a
coverage gate explicit in CI, set `REDIS_KIT_COVERAGE_MINIMUM_EXPRESSION` and
`REDIS_KIT_COVERAGE_MINIMUM_BRANCH` to integer percentages from 0 through 100.

## License

MIT
