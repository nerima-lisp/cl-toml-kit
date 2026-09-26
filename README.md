# cl-toml-kit

`cl-toml-kit` is a Common Lisp TOML v1.1.0 reader and writer for SBCL. It uses
native hash tables, simple vectors, scalar values, and cl-date-kit date types.

## Quick Start

```lisp
(cl-toml-kit:parse "title = \"TOML\"")
(cl-toml-kit:encode (make-hash-table :test 'equal))
```

Tables use string keys and `:test 'equal`; arrays use `simple-vector`. TOML
false is `+toml-false+`, recognized with `toml-false-p`. `nil` and lists are
not TOML values.

## Documentation

- [Data model](docs/src/guide/data-model.md)
- [API reference](docs/src/reference/api.md)
- [Conditions](docs/src/reference/conditions.md)
- [Architecture](docs/design/architecture.md)

## Development

The supported build is SBCL through Nix. Run the complete check with:

```console
timeout 1800 nix flake check
```

Diagnostic benchmarks run with `timeout 600 sbcl --script run-benchmarks.lisp`.

## License

MIT. See [`LICENSE`](LICENSE).
