# cl-toml-kit

`cl-toml-kit` is a Common Lisp TOML v1.1.0 reader and writer for SBCL.
It preserves TOML's distinction between integer and floating-point values,
ordered tables, empty collections, and the four TOML date/time types.

## Status

The public API is intentionally small while the reader and writer are being
implemented in parallel:

```lisp
(cl-toml-kit:parse string)
(cl-toml-kit:encode value)
```

Both are ordinary functions. Conditions are signaled as
`toml-parse-error` or `toml-encoding-error`, with source location available
for parse failures.

## Development

The supported build is SBCL through Nix. Run the complete check with:

```console
timeout 1800 nix flake check
```

The architecture and ownership contract for the parallel reader and writer
implementation is in [`docs/design/architecture.md`](docs/design/architecture.md).

## License

MIT. See [`LICENSE`](LICENSE).
