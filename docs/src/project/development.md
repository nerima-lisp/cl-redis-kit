# Development

## Reproducible commands

From the project root:

~~~sh
nix develop
nix run .#test
nix flake check
nix build .#coverage
nix build .#tls
nix build .#resilience
nix build .#docs
nix fmt
~~~

`nix flake check` evaluates the formatter, test, lint, TLS, resilience, and
documentation checks exposed by the flake. `nix run .#test` runs the core test
application. The coverage, optional integration packages, and documentation
site are separate outputs.

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

The development shell includes MkDocs with the Material theme. Run the strict
build from the repository root:

~~~sh
mkdocs build --strict -f docs/mkdocs.yml --site-dir /tmp/cl-redis-kit-docs
~~~

The configuration uses `docs/src` as its source directory. A successful build
should produce an `index.html` in the chosen site directory.
