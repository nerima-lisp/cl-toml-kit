# Getting Started

`cl-toml-kit` is a TOML v1.1.0 reader and writer for SBCL. The runtime depends
on [`cl-parser-kit`](https://github.com/nerima-lisp/cl-parser-kit),
[`cl-date-kit`](https://github.com/nerima-lisp/cl-date-kit), and
[`cl-codec-kit`](https://github.com/nerima-lisp/cl-codec-kit); only the test
system additionally uses [`cl-weave`](https://github.com/nerima-lisp/cl-weave)
and [`cl-json-kit`](https://github.com/nerima-lisp/cl-json-kit).

## With Nix

The repository is a Nix flake. To build the ASDF system:

```sh
nix build github:nerima-lisp/cl-toml-kit
```

The flake also exposes per-system attributes:

```sh
# Run the test suite, coverage gate, docs build, formatting, and paredit
# lint as reproducible derivations.
nix flake check

# Enter a devShell with SBCL and paredit-cli.
nix develop
```

## With ASDF

For each runtime dependency, download the source archive from its project link
above at the minimum tagged version listed under
[Supported versions](#supported-versions), then unpack it into a separate
directory. ASDF must be able to find this checkout and all three dependency
systems. Set `CL_SOURCE_REGISTRY` to register each project root:

```sh
export CL_SOURCE_REGISTRY='(:source-registry (:directory "/path/to/cl-toml-kit/") (:directory "/path/to/cl-parser-kit/") (:directory "/path/to/cl-date-kit/") (:directory "/path/to/cl-codec-kit/") :inherit-configuration)'
```

Start an SBCL REPL in the checkout, then load the system:

```lisp
(require :asdf)
(asdf:load-system "cl-toml-kit")
```

ASDF `:version` dependencies specify minimum system versions; they do not lock
source revisions ([ASDF manual](https://asdf.common-lisp.dev/asdf.html)). Nix
builds use the input revisions recorded in this project's
[`flake.lock`](https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-flake.html#lock-files).

Everything a caller needs is exported from the single `cl-toml-kit` package.
Every example on this site references symbols with the `cl-toml-kit:` prefix.

## Supported versions

`cl-toml-kit` targets SBCL only and reads and writes TOML v1.1.0. The
runtime dependencies are `cl-parser-kit` (1.1.1 or newer), `cl-date-kit`
(1.2.0 or newer), and `cl-codec-kit` (0.6.0 or newer). The test system also
requires `cl-weave` (1.4.0 or newer) and `cl-json-kit` (1.2.0 or newer).

## Running tests

The standalone test system requires the runtime dependencies above and both
test dependencies. Download their source archives at the minimum tagged
versions above, then add `:directory` entries for their roots to the
`CL_SOURCE_REGISTRY` form before running:

```sh
sbcl --script run-tests.lisp
```

## Parse a document

`parse` reads a TOML string and returns an `equal` hash table with string
keys:

```lisp
(defparameter *document*
  (cl-toml-kit:parse (format nil "title = \"TOML\"~%active = false~%")))

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
;; TOML output (the returned string ends with a newline):
;; title = "TOML"
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
;; => "Unsupported TOML value (value list)"
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
