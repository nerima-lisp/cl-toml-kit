# cl-toml-kit

A Common Lisp TOML v1.1.0 reader and writer for SBCL. Tables, arrays, and
scalar values map to a native Lisp model, dates stay typed with cl-date-kit,
and failures signal structured conditions.

**Documentation: <https://nerima-lisp.github.io/cl-toml-kit/>**

## Install

```sh
nix build github:nerima-lisp/cl-toml-kit
```

or put the repository where ASDF can find it:

```lisp
(asdf:load-system "cl-toml-kit")
```

The runtime depends on `cl-parser-kit` and `cl-date-kit`; only the test system
additionally uses `cl-weave`. SBCL is the supported implementation. See
[Getting Started](https://nerima-lisp.github.io/cl-toml-kit/getting-started/).

## Use

```lisp
(defparameter *document*
  (cl-toml-kit:parse "title = \"TOML\"\nactive = false\n"))

(gethash "title" *document*)                            ; => "TOML", T
(cl-toml-kit:toml-false-p (gethash "active" *document*)) ; => T

(let ((table (make-hash-table :test 'equal)))
  (setf (gethash "title" table) "TOML")
  (cl-toml-kit:encode table))                           ; => "title = \"TOML\"\n"
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
(cl-toml-kit:edit-toml-bytes source '("server" "port") 8080)
(cl-toml-kit:delete-toml source '("server" "deprecated"))
```

`source` and the result are UTF-8 byte vectors. A path string is one key, not a
dot-separated path: `("a.b")` addresses the key named `a.b`, while
`("a" "b")` addresses a nested table value. Array elements use zero-based
integer components. Edits are parsed again and rejected if the result does
not have the requested document value. Use `delete-toml` or `:delete t` for
deletion; omitting the edit value is not deletion.

See the [format-preserving editing API reference](https://nerima-lisp.github.io/cl-toml-kit/reference/api/#format-preserving-editing)
for the supported rejection conditions.

## Why cl-toml-kit?

**TOML shape is never guessed from Lisp contents.** A table is an `equal`
hash table with string keys, and an array is a simple vector. `nil` and lists
are not TOML values, so a list can never be silently written as a table, an
array, or a null.

**Dates stay typed.** The four cl-date-kit date and time types are first-class
TOML values, so a date never makes a round trip through a string.

**`false` is distinct.** `+toml-false+` is an opaque sentinel, kept separate
from Lisp `nil` and from `t`.

**Structured diagnostics.** Parse and encode failures signal typed conditions
that carry source coordinates, an expected-token description, and a path into
the document.

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

`nil` and lists are not TOML values; there is no TOML null. Full rules are in
the [Data Model](https://nerima-lisp.github.io/cl-toml-kit/guide/data-model/).

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

```sh
timeout 1800 nix flake check   # tests, docs build, formatting, paredit lint
sbcl --script run-tests.lisp   # tests only
```

Diagnostic benchmarks run with `sbcl --script run-benchmarks.lisp`.

## License

MIT. See [LICENSE](LICENSE).
