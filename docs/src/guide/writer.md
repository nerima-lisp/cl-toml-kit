# Writer

`encode` returns TOML text, and `write-toml` writes the same representation to
a character stream. Both accept a top-level `equal` hash table whose keys are
strings. Tables, vectors, strings, signed 64-bit integers, double floats,
`t`, `+toml-false+`, and the four cl-date-kit date types are supported.

Scalar entries are emitted first in hash-table traversal order, followed by
non-empty tables as `[path]` headers and vectors whose elements are all tables
as repeated `[[path]]` headers. This is applied recursively. Arrays and tables
in positions without a header are inline values; an empty table is `{}`.
Lines end in LF. Keys use bare-key syntax for ASCII letters, digits, `-`, and
`_`; all other keys use a basic string. Basic strings escape `\b`, `\t`,
`\n`, `\f`, `\r`, quotes, backslashes, U+0000 through U+001F, and U+007F.

Floats use `inf`, `-inf`, `nan`, decimal notation for ordinary values, and
an exponent when needed. Integer-valued floats retain `.0`, so `1.0` is not
written as the integer `1`.

Invalid values signal `toml-encoding-error`. Its
`toml-encoding-error-path` accessor contains the path from the root table,
including vector indexes, and its message includes a printed description of
the rejected value. The top level must be an `equal` hash table and every key
must be a string. Integers outside signed 64-bit range and unsupported Lisp
values are rejected. `write-toml` writes directly to the supplied stream;
only `encode` allocates the output string.

For example:

```lisp
(encode (let ((table (make-hash-table :test 'equal)))
          (setf (gethash "title" table) "TOML"
                (gethash "enabled" table) t)
          table))
;; => "title = \"TOML\"\nenabled = true\n"
```
