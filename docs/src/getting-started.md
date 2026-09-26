# Getting Started

`cl-toml-kit` is a TOML v1.1.0 reader and writer for SBCL. The runtime depends
on [`cl-parser-kit`](https://github.com/nerima-lisp/cl-parser-kit) and
[`cl-date-kit`](https://github.com/nerima-lisp/cl-date-kit); only the test
system additionally uses [`cl-weave`](https://github.com/nerima-lisp/cl-weave).

## With Nix

The repository is a Nix flake. To build the ASDF system:

```sh
nix build github:nerima-lisp/cl-toml-kit
```

The flake also exposes per-system attributes:

```sh
# Run the test suite, docs build, formatting, and paredit lint
# as reproducible derivations.
nix flake check

# Enter a devShell with SBCL and paredit-cli.
nix develop
```

## With ASDF

Put the repository where ASDF can find it, for example under `~/common-lisp/`
or a directory on your `CL_SOURCE_REGISTRY`, then load it:

```lisp
(asdf:load-system "cl-toml-kit")
```

Everything a caller needs is exported from the single `cl-toml-kit` package.
Every example on this site references symbols with the `cl-toml-kit:` prefix.

## Supported runtime

`cl-toml-kit` targets **SBCL** only and reads and writes TOML v1.1.0. The
runtime dependencies are `cl-parser-kit` (1.1.1 or newer) and `cl-date-kit`
(1.1.0 or newer).

## Verifying the install

The canonical gate is `nix flake check`, wrapped by the contract as:

```console
timeout 1800 nix flake check
```

It runs the test suite, builds the documentation, checks formatting, and lints
the sources with paredit-cli. To run only the test suite:

```sh
sbcl --script run-tests.lisp
```

## Parse a document

`parse` reads a TOML string and returns an `equal` hash table with string
keys:

```lisp
(defparameter *document*
  (cl-toml-kit:parse "title = \"TOML\"\nactive = false\n"))

(gethash "title" *document*)                             ; => "TOML", T
(cl-toml-kit:toml-false-p (gethash "active" *document*)) ; => T
```

TOML `false` is the opaque sentinel `+toml-false+`, not Lisp `nil`. Test it
with `toml-false-p` rather than by identity or printed form. `parse-file`
reads from a pathname instead of a string.

## Encode a document

`encode` returns TOML text for an `equal` hash table:

```lisp
(let ((table (make-hash-table :test 'equal)))
  (setf (gethash "title" table) "TOML")
  (cl-toml-kit:encode table))
;; => "title = \"TOML\"\n"
```

`write-toml` writes the same representation to an existing character stream.
See [Writer](guide/writer.md) for nested tables and arrays of tables.

## Handle errors

The writer rejects values that are not valid TOML with a typed condition:

```lisp
(handler-case
    (cl-toml-kit:encode
     (let ((table (make-hash-table :test 'equal)))
       (setf (gethash "name" table) '(1 2 3))
       table))
  (cl-toml-kit:toml-encoding-error (condition)
    (cl-toml-kit:toml-encoding-error-message condition)))
;; => "Unsupported TOML value (value (1 2 3))"
```

`toml-encoding-error-path` names the location of the rejected value. Malformed
input signals `toml-parse-error`, which carries source coordinates, a path,
and an expected-token description. See
[Conditions](reference/conditions.md) for every reader on these condition
objects.

## Next steps

- [Data Model](guide/data-model.md): how each TOML value maps to Lisp.
- [Reader](guide/reader.md): every `parse` and `parse-file` detail.
- [Writer](guide/writer.md): nested tables, arrays of tables, and number
  formats.
- [Troubleshooting](guide/troubleshooting.md): answers to common questions.
- [API reference](reference/api.md): every exported symbol.
- [Conditions](reference/conditions.md): the typed conditions and their
  readers.
- [Compatibility](reference/compatibility.md): the compatibility promise.
- [Architecture](reference/architecture.md): how the reader and writer are
  built.
