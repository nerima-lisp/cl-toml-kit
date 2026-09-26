# cl-toml-kit

`cl-toml-kit` is a Common Lisp TOML v1.1.0 reader and writer for SBCL. It maps
TOML documents to a native Lisp value model: `equal` hash tables for tables,
simple vectors for arrays, signed 64-bit integers and double floats for
numbers, an opaque sentinel for `false`, and the four cl-date-kit types for
dates and times. Failures signal typed conditions that carry source
coordinates and a path into the document.

```lisp
(cl-toml-kit:encode (cl-toml-kit:parse "title = \"TOML\""))
;; => "title = \"TOML\"\n"
```

## Next steps

- [Getting Started](getting-started.md): install with Nix or ASDF and read
  your first document.
- [Data Model](guide/data-model.md): how each TOML value maps to Lisp.
- [Reader](guide/reader.md): parsing strings and files.
- [Writer](guide/writer.md): encoding values as TOML text.
- [Troubleshooting](guide/troubleshooting.md): answers to common questions.
- [API reference](reference/api.md): every exported symbol.
- [Conditions](reference/conditions.md): the typed conditions and their readers.
- [Compatibility](reference/compatibility.md): the compatibility promise.
- [Architecture](reference/architecture.md): how the reader and writer are
  built.
