# Development

## Reproducible commands

From the project root:

~~~sh
nix develop
nix run .#test
nix flake check
nix build .#coverage
nix build .#tls
nix fmt
~~~

`nix flake check` evaluates the formatter, test, lint, and TLS checks exposed
by the flake. `nix run .#test` runs the test application. The coverage and
TLS package builds are separate outputs.

## Direct test execution

Inside the development shell, the test runner can be invoked directly:

~~~sh
sbcl --non-interactive \
  --load run-tests.lisp
~~~

The test plan uses the project's test packages and includes the optional
resilience integration when its dependencies are available. Keep the selected
test set non-empty when changing the runner or plan.

## Documentation build

Install MkDocs with the Material theme, then run the strict build from the
repository root:

~~~sh
mkdocs build --strict -f docs/mkdocs.yml --site-dir /tmp/cl-redis-kit-docs
~~~

The configuration uses `docs/src` as its source directory. A successful build
should produce an `index.html` in the chosen site directory.
