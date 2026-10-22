# cl-toml-kit

A Common Lisp TOML v1.1.0 reader and writer for SBCL. Tables, arrays, and
scalar values map to a native Lisp model, dates stay typed with cl-date-kit,
and failures signal structured conditions.

**Documentation: <https://nerima-lisp.github.io/cl-toml-kit/>**

## Install

On `x86_64-linux` with Nix flakes enabled, build the package with Nix:

```sh
nix build github:nerima-lisp/cl-toml-kit
```

Or load it with ASDF after setting up the source registry as described in
[Getting Started](https://nerima-lisp.github.io/cl-toml-kit/getting-started/):

```lisp
(asdf:load-system "cl-toml-kit")
```

The runtime depends on `cl-parser-kit`, `cl-date-kit`, and `cl-codec-kit`; the
test system additionally uses `cl-weave` and `cl-json-kit`.

## Use

```lisp
(defparameter *document*
  (cl-toml-kit:parse
   (format nil "title = \"TOML\"~%active = false~%")))

(gethash "title" *document*)                            ; => "TOML", T
(cl-toml-kit:toml-false-p (gethash "active" *document*)) ; => T

(let ((table (make-hash-table :test 'equal)))
  (setf (gethash "title" table) "TOML")
  (cl-toml-kit:encode table))
```

`+toml-false+` is an opaque sentinel. Test it with `toml-false-p` rather than
depending on its printed form.

`parse-file` reads a document from a pathname, `write-toml` writes to an
existing character stream, and `encode` returns the TOML text as a string. See
[Reader](https://nerima-lisp.github.io/cl-toml-kit/guide/reader/) and
[Writer](https://nerima-lisp.github.io/cl-toml-kit/guide/writer/) for the full
surface.

### Format-preserving editing

The editing API changes one parsed value while retaining unrelated source
bytes, including comments, whitespace, and line endings:

```lisp
(let* ((source
         (sb-ext:string-to-octets
          (format nil "[server]~%port = 8000~%deprecated = true~%")
          :external-format :utf-8))
       (updated (cl-toml-kit:edit-toml source '("server" "port") 8080)))
  (cl-toml-kit:delete-toml updated '("server" "deprecated")))
```

`source` and the result are UTF-8 byte vectors. A path string is one key, not a
dot-separated path: `("a.b")` addresses the key named `a.b`, while
`("a" "b")` addresses a nested table value. Array elements use zero-based
integer components. Each edit result is parsed again and checked against the
original document with the requested change applied. Call
`cl-toml-kit:delete-toml` or `(cl-toml-kit:edit-toml source path nil :delete t)`
to delete a value; omitting the edit value alone is not deletion.

See the [editing API reference](docs/src/reference/api.md#format-preserving-editing) for
the supported rejection conditions.

## Why cl-toml-kit?

**TOML shape is never guessed from Lisp contents.** A table is an `equal`
hash table with string keys, and an array is a simple vector. `nil` and lists
are not TOML values, so a list can never be silently written as a table, an
array, or a null.

**Structured diagnostics.** Parse failures signal `toml-parse-error` with
source coordinates and optional expected-input and path details. Encoding
failures signal `toml-encoding-error` with a message and optional value path.

| TOML | Reader result | Writer input |
| --- | --- | --- |
| table | `equal` hash table with string keys | `equal` hash table with string keys |
| array | simple vector | simple vector |
| string | string | string |
| integer | signed 64-bit integer | signed 64-bit integer |
| float | double float | double float |
| `true` | `t` | `t` |
| `false` | `+toml-false+` | `+toml-false+` |
| offset date-time | `cl-date-kit:offset-date-time` | `cl-date-kit:offset-date-time` |
| local date-time | `cl-date-kit:local-date-time` | `cl-date-kit:local-date-time` |
| local date | `cl-date-kit:local-date` | `cl-date-kit:local-date` |
| local time | `cl-date-kit:local-time` | `cl-date-kit:local-time` |

## Documentation

- [Getting Started](https://nerima-lisp.github.io/cl-toml-kit/getting-started/)
- [Data Model](https://nerima-lisp.github.io/cl-toml-kit/guide/data-model/)
- [Reader](https://nerima-lisp.github.io/cl-toml-kit/guide/reader/)
- [Writer](https://nerima-lisp.github.io/cl-toml-kit/guide/writer/)
- [Troubleshooting](https://nerima-lisp.github.io/cl-toml-kit/guide/troubleshooting/)
- [API reference](https://nerima-lisp.github.io/cl-toml-kit/reference/api/)
- [Conditions](https://nerima-lisp.github.io/cl-toml-kit/reference/conditions/)
- [Compatibility](https://nerima-lisp.github.io/cl-toml-kit/reference/compatibility/)
- [Architecture](https://nerima-lisp.github.io/cl-toml-kit/reference/architecture/)

## Development

With Nix flakes enabled, run the full flake checks on `x86_64-linux`; CI runs
them there:

```sh
nix flake check
```

On macOS, run the Lisp test suite with SBCL and the ASDF dependencies listed
in [Getting Started](https://nerima-lisp.github.io/cl-toml-kit/getting-started/):

```sh
sbcl --script run-tests.lisp
```

Diagnostic benchmarks run with `sbcl --script run-benchmarks.lisp`.

## License

MIT. See [LICENSE](LICENSE).
