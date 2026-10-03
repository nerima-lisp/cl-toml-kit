# Writing TOML

There are two entry points. `encode` returns the TOML text as a string.
`write-toml` writes the same text to a character stream you supply and returns
the value you passed in. Both apply the rules on this page; see the
[API reference](../reference/api.md#encode) for the exact signatures.

## Output shape

The top-level value must be a hash table with test `equal` and string keys.
Within each table, the writer makes three passes over the hash table:

1. Entries whose value is a scalar or an array that is not an array of
   tables are emitted first as `key = value` lines.
2. Entries whose value is a table are emitted next as a `[dotted.path]`
   header followed by that table's entries.
3. Entries whose value is a non-empty `simple-vector` whose elements are all
   hash tables are emitted last as repeated `[[dotted.path]]` headers, one per
   element.

The passes recurse into every nested table, so a table inside a table gets
`[outer.inner]` headers, and so on. Every line ends with a newline, and so
does the output.

An empty table is still a table entry. It is emitted as a `[path]` header with
no lines after it, not as `{}`. The inline form `{}` appears only when a table
is reached as a value rather than as a table entry: as an array element, or as
an entry of an inline table. Arrays of tables at table level always take the
`[[...]]` header form, so the arrays you see inline are arrays that are
themselves values, such as an array inside a mixed array or inside an inline
table. An empty vector is `[]`, and an array of tables must be non-empty to be
recognized as one.

A worked example with all three entry kinds:

```lisp
(let ((table (make-hash-table :test 'equal)))
  (setf (gethash "title" table) "TOML"
        (gethash "enabled" table) cl-toml-kit:+toml-false+)
  (setf (gethash "server" table)
        (let ((server (make-hash-table :test 'equal)))
          (setf (gethash "host" server) "example.com"
                (gethash "port" server) 8080)
          server))
  (setf (gethash "points" table)
        (vector (let ((point (make-hash-table :test 'equal)))
                  (setf (gethash "x" point) 1)
                  point)
                (let ((point (make-hash-table :test 'equal)))
                  (setf (gethash "y" point) 2)
                  point)))
  (cl-toml-kit:encode table))
;; => "title = \"TOML\"\nenabled = false\n[server]\nhost = \"example.com\"\nport = 8080\n[[points]]\nx = 1\n[[points]]\ny = 2\n"
```

## Keys

A key is written in bare-key syntax when it is non-empty and every character
is an ASCII `A-Z`, `a-z`, `0-9`, `-`, or `_`. Any other key is written as a
basic string using the escaping rules from [Strings](#strings), so the empty
key becomes `""` and a key containing a space or a dot is quoted.

Dotted paths apply the same rule per component and join the components with
`.`. A component containing a literal dot is quoted and stays one component:

```lisp
(let ((table (make-hash-table :test 'equal)))
  (setf (gethash "plain-key" table) 1
        (gethash "key with spaces" table) 2
        (gethash "" table) 3)
  (cl-toml-kit:encode table))
;; => "plain-key = 1\n\"key with spaces\" = 2\n\"\" = 3\n"
```

## Strings

The writer uses TOML basic strings wherever a string value or key appears. The
escape set is `\b`, `\t`, `\n`, `\f`, `\r`, `\"`, and `\\`. Control characters
U+0000 through U+001F and U+007F that are not in that set are written as
`\uXXXX` with four uppercase hex digits. Every other character, including all
non-ASCII characters, is written literally, so UTF-8 text passes through
unchanged:

```lisp
(cl-toml-kit:encode
 (let ((table (make-hash-table :test 'equal)))
   (setf (gethash "text" table)
         (format nil "tab:~C bel:~C back:~C uni:λ" #\Tab #\Bell #\Backspace))
   table))
;; => "text = \"tab:\\t bel:\\u0007 back:\\b uni:λ\"\n"
```

## Numbers

Integers must fit the signed 64-bit range described in
[Data Model and Mapping](data-model.md#integers); anything outside signals
`toml-encoding-error` (see [Errors](#errors)).

Floats are printed with three special cases first: `nan` for NaN, and `inf` or
`-inf` for the infinities. Everything else goes through `prin1` with
`*read-default-float-format*` bound to `double-float`. That binding keeps a
whole float looking like a float: `2.0` is written as `2.0`, never as the
integer `2`, and exponents use `e`:

```lisp
(cl-toml-kit:encode
 (let ((table (make-hash-table :test 'equal)))
   (setf (gethash "whole" table) 2.0d0
         (gethash "tiny" table) 1.0d-5
         (gethash "infinity" table) sb-ext:double-float-positive-infinity)
   table))
;; => "whole = 2.0\ntiny = 1.0e-5\ninfinity = inf\n"
```

The exact digit count and exponent spelling are whatever SBCL's float printer
produces for the value; do not rely on a specific number of digits.

## Date and time values

Date values must be the cl-date-kit objects described in
[Data Model and Mapping](data-model.md#date-and-time-values); anything else is
an unsupported value.

`offset-date-time`, `local-date-time`, and `local-time` are formatted through
cl-date-kit's RFC 3339 profile: `cl-date-kit:format-offset-date-time`,
`cl-date-kit:format-local-date-time`, and `cl-date-kit:format-local-time`,
each with `:profile :rfc3339`. `local-date` uses the plain formatter
`cl-date-kit:format-local-date`. See the
[cl-date-kit documentation](https://nerima-lisp.github.io/cl-date-kit/) for
the profiles' exact output.

## Errors

`toml-encoding-error` is the one condition the writer signals. You get it for:

- a top-level value that is not a hash table;
- a hash table whose test is not `equal`, at any depth (`make-hash-table`
  defaults to `eql`, so tables created without `:test 'equal` are rejected);
- a non-string key;
- an integer outside the signed 64-bit range;
- any other unsupported Lisp value, including `nil` and lists.

The error message includes a printed form of the rejected value, and the
`toml-encoding-error-path` accessor holds the path from the root table,
including vector indices. See
[Conditions](../reference/conditions.md#toml-encoding-error) for the full
condition details.

A concrete example:

```lisp
(let ((table (make-hash-table :test 'equal)))
  (setf (gethash "big" table) (ash 1 63))
  (cl-toml-kit:encode table))
;; signals TOML encode error at ("big"):
;; "Integer is outside TOML's signed 64-bit range (value 9223372036854775808)"
```

`write-toml` additionally runs `(check-type stream stream)` before writing
anything, so passing a non-stream signals `type-error` instead. Neither entry
point mutates the value you pass in; only the stream receives output.

Both entry points accept `:max-depth`, which defaults to 512 aggregate levels.
Pass a positive integer to lower the limit or `nil` to disable it. Exceeding
the limit signals `toml-encoding-error` with the path of the nested value.
