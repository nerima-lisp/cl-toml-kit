# API Reference

Everything a caller needs is exported from the single `cl-toml-kit` package:
the reader and writer entry points, the native value types and predicates,
and the structured conditions. Nothing else is exported.

Symbols are grouped as they are exported in `src/package.lisp`. The
[data model](../guide/data-model.md) defines the value mapping shared by
reading and writing, and [Conditions](conditions.md) documents the condition
hierarchy in full.

## Reader and Writer

### `parse`

```lisp
(cl-toml-kit:parse source &key source-name)
  => hash-table
```

Parse a TOML document and return its top-level table as an `equal` hash
table.

| Argument | Type | Default | Meaning |
| --- | --- | --- | --- |
| `source` | `string` or `stream` | n/a | The TOML document, as a string or a character input stream. |
| `source-name` | designator | `nil` | Identifies the source in diagnostics; stored in `toml-parse-error-source-name`. |

**Returns**: the top-level table, a hash table with `:test 'equal`. Keys and
values use the [native value mapping](../guide/data-model.md).

**Signals**: `toml-parse-error` for malformed TOML.

**Example**:

```lisp
(cl-toml-kit:parse "title = \"TOML\"")
;; => #<HASH-TABLE :TEST EQUAL :COUNT 1>
```

See also: [Reader](../guide/reader.md), [Conditions](conditions.md#toml-parse-error).

### `parse-file`

```lisp
(cl-toml-kit:parse-file pathname)
  => hash-table
```

Read the file at `pathname`, a pathname designator, and parse its contents as
one TOML document.

**Returns**: the top-level table, a hash table with `:test 'equal`.

**Signals**: `toml-parse-error` for malformed TOML. The usual file conditions
(for example `file-error`) apply when the file cannot be read.

**Example**:

```lisp
(cl-toml-kit:parse-file #p"config.toml")
;; => #<HASH-TABLE :TEST EQUAL :COUNT 3>
```

See also: [Reader](../guide/reader.md).

### `encode`

```lisp
(cl-toml-kit:encode value)
  => string
```

Serialize `value` to a TOML document and return it as a string. `value` is
the top-level table, an `equal` hash table whose keys are strings.

**Returns**: the TOML text.

**Signals**: `toml-encoding-error` for an invalid top level, non-string keys,
out-of-range integers, or unsupported values.

**Example**:

```lisp
(cl-toml-kit:encode
 (let ((table (make-hash-table :test 'equal)))
   (setf (gethash "title" table) "TOML")
   table))
;; => "title = \"TOML\"\n"
```

See also: [Writer](../guide/writer.md), [Conditions](conditions.md#toml-encoding-error).

### `write-toml`

```lisp
(cl-toml-kit:write-toml value stream)
  => value
```

Write `value` as TOML text to the character `stream` and return the original
`value`. The stream is left open.

**Returns**: `value`.

**Signals**: `type-error` if `stream` is not a stream (`check-type`), and
`toml-encoding-error` for invalid values.

**Example**:

```lisp
(with-output-to-string (out)
  (cl-toml-kit:write-toml
   (let ((table (make-hash-table :test 'equal)))
     (setf (gethash "n" table) 1)
     table)
   out))
;; => "n = 1\n"
```

See also: [Writer](../guide/writer.md).

## Format-preserving editing

### `edit-toml`

```lisp
(cl-toml-kit:edit-toml source path &optional new-value &key delete)
  => octet-vector
```

Edit a UTF-8 TOML document represented by a vector of unsigned-byte 8 values.
`path` is a string or a sequence of string keys and zero-based non-negative
array indices. Existing values are replaced when `new-value` is supplied.
Use `:delete t` with `new-value` set to `nil`, or use `delete-toml`, to remove
an existing value. The returned
bytes retain the BOM, comments, key order, whitespace,
line-ending style, string delimiters, and table kind outside the edited span.

```lisp
(cl-toml-kit:edit-toml
 #(110 97 109 101 32 61 32 34 111 108 100 34 32 32 35 32 107 101 101 112 13 10)
 '("name")
 "new")
;; => bytes for "name = \"new\"  # keep\r\n"
```

Adding a missing leaf uses the containing table's assignment style. Structural
edits that would require choosing among multiple array-table elements,
re-homing dotted keys, or assigning comments or delimiters to a deleted span
signal `toml-format-preservation-error`.

### `edit-toml-bytes` and `delete-toml`

```lisp
(cl-toml-kit:edit-toml-bytes source path &optional new-value &key delete)
(cl-toml-kit:delete-toml source path)
  => octet-vector
```

`edit-toml-bytes` is the byte-oriented spelling of `edit-toml`; `delete-toml`
is equivalent to `(edit-toml source path nil :delete t)`. Neither function mutates
the input vector.

## Native Values

### `+toml-false+`

The opaque sentinel that represents TOML `false`. It is a load-time global,
not a constant, and it is not `nil`. Its identity is what matters, so test for
it with `toml-false-p` rather than depending on its value or printed form.

```lisp
(cl-toml-kit:toml-false-p cl-toml-kit:+toml-false+) ; => t
(eq cl-toml-kit:+toml-false+ nil) ; => nil
```

See also: [Data model](../guide/data-model.md).

### `toml-false-p`

```lisp
(cl-toml-kit:toml-false-p value)
  => generalized-boolean
```

Return true if `value` is `eq` to `+toml-false+`.

**Returns**: a boolean.

**Signals**: `none`.

### `toml-value`

A type: the union of every native TOML value type.

```lisp
(or hash-table simple-vector string (signed-byte 64) double-float
    (eql t) toml-false-sentinel cl-date-kit:offset-date-time
    cl-date-kit:local-date-time cl-date-kit:local-date cl-date-kit:local-time)
```

`toml-false-sentinel` is the unexported type of `+toml-false+`. As a type,
`toml-value` matches any `hash-table`, regardless of its test. `toml-value-p`
and `toml-value-kind` are stricter: they also require the `equal` hash-table
test (see `toml-table-p`).

See also: [Data model](../guide/data-model.md).

### `toml-value-p`

```lisp
(cl-toml-kit:toml-value-p value)
  => generalized-boolean
```

Return true if `toml-value-kind` returns non-nil, that is, if `value` is a
native TOML value with the `equal` hash-table test applied to tables.

**Returns**: a boolean.

**Signals**: `none`.

### `toml-value-kind`

```lisp
(cl-toml-kit:toml-value-kind value)
  => keyword or nil
```

Return the TOML kind of `value`: `:table`, `:array`, `:string`, `:integer`,
`:float`, `:true`, `:false`, `:offset-date-time`, `:local-date-time`,
`:local-date`, or `:local-time`. Return `nil` for a value that is not a TOML
value. A hash table counts as a table only with the `equal` test.

**Signals**: `none`.

**Example**:

```lisp
(cl-toml-kit:toml-value-kind (make-hash-table :test 'equal)) ; => :table
(cl-toml-kit:toml-value-kind (make-hash-table :test 'eql)) ; => nil
(cl-toml-kit:toml-value-kind #(1 2 3)) ; => :array
(cl-toml-kit:toml-value-kind nil) ; => nil
```

### `toml-value-typecase`

```lisp
(cl-toml-kit:toml-value-typecase value &body clauses)
  => result of the selected clause
```

Dispatch `value` by its TOML kind. Clause keys are the kind keywords of
`toml-value-kind`; `t` supplies the otherwise clause. The macro expands to a
single Common Lisp `typecase`.

Unknown kind keywords are rejected at macro expansion time. In a `:table`
clause whose value is a hash table without the `equal` test, the expansion
signals `toml-encoding-error` with the message `Invalid TOML table`. When no
clause matches and there is no `t` clause, it signals `toml-encoding-error`
with the message `Not a TOML value`.

**Signals**: `toml-encoding-error` in the two cases above.

**Example**:

```lisp
(flet ((kind-name (value)
         (cl-toml-kit:toml-value-typecase value
           (:table "table")
           (:array "array")
           (:integer "integer")
           (t "other"))))
  (list (kind-name (make-hash-table :test 'equal))
        (kind-name #(1 2 3))
        (kind-name 42)
        (kind-name "x")))
;; => ("table" "array" "integer" "other")
```

See also: [Data model](../guide/data-model.md).

### `toml-table`

A type alias for `hash-table`. Prefer `toml-table-p` when the `equal` test
matters.

### `toml-table-p`

```lisp
(cl-toml-kit:toml-table-p value)
  => generalized-boolean
```

Return true if `value` is a hash table whose test is `equal`. The check is
O(1): it looks at the table's test, not its contents.

**Returns**: a boolean.

**Signals**: `none`.

### `toml-array`

A type alias for `simple-vector`.

### `toml-array-p`

```lisp
(cl-toml-kit:toml-array-p value)
  => generalized-boolean
```

Return true if `value` is a simple vector.

**Returns**: a boolean.

**Signals**: `none`.

### `toml-integer`

A type alias for `(signed-byte 64)`, the signed 64-bit integers.

### `toml-integer-p`

```lisp
(cl-toml-kit:toml-integer-p value)
  => generalized-boolean
```

Return true if `value` is a signed 64-bit integer.

**Returns**: a boolean.

**Signals**: `none`.

### `toml-float`

A type alias for `double-float`.

### `toml-float-p`

```lisp
(cl-toml-kit:toml-float-p value)
  => generalized-boolean
```

Return true if `value` is a double-float.

**Returns**: a boolean.

**Signals**: `none`.

## Conditions

The condition hierarchy is documented in full in
[Conditions](conditions.md); the entries here list the exported types and
accessors only.

### `toml-kit-error`

A condition, subtype of `error`. It is the base of every condition this
library signals and carries no slots.

See also: [The shared base condition](conditions.md#the-shared-base-condition).

### `toml-parse-error`

A condition, subtype of `toml-kit-error`, signalled for malformed TOML input.
Its readers, with their default values: `toml-parse-error-source-name`
(`nil`), `toml-parse-error-position` (`0`), `toml-parse-error-line` (`1`),
`toml-parse-error-column` (`1`), `toml-parse-error-path` (`nil`),
`toml-parse-error-expected` (`nil`), `toml-parse-error-context` (`"TOML"`),
and `toml-parse-error-text` (`""`).

See also: [TOML parse error](conditions.md#toml-parse-error).

### `toml-parse-error-source-name`

Return the `source-name` designator supplied to `parse`, or `nil` if none was
given.

**Signals**: `none`.

See also: [TOML parse error](conditions.md#toml-parse-error).

### `toml-parse-error-position`

Return the zero-based character offset in the input where parsing failed.

**Signals**: `none`.

See also: [TOML parse error](conditions.md#toml-parse-error).

### `toml-parse-error-line`

Return the one-based line number where parsing failed.

**Signals**: `none`.

See also: [TOML parse error](conditions.md#toml-parse-error).

### `toml-parse-error-column`

Return the one-based column number where parsing failed.

**Signals**: `none`.

See also: [TOML parse error](conditions.md#toml-parse-error).

### `toml-parse-error-path`

Return the path of table keys and vector indices to the failure, or `nil`.

**Signals**: `none`.

See also: [TOML parse error](conditions.md#toml-parse-error).

### `toml-parse-error-expected`

Return a short description of what the parser expected, or `nil`.

**Signals**: `none`.

See also: [TOML parse error](conditions.md#toml-parse-error).

### `toml-parse-error-context`

Return the context label of the failure; defaults to `"TOML"`.

**Signals**: `none`.

See also: [TOML parse error](conditions.md#toml-parse-error).

### `toml-parse-error-text`

Return a bounded, sanitized snippet of the input near the failure.

**Signals**: `none`.

See also: [TOML parse error](conditions.md#toml-parse-error).

### `toml-encoding-error`

A condition, subtype of `toml-kit-error`, signalled by the writer for values
that cannot be represented in TOML. Its readers are
`toml-encoding-error-message` (default `"TOML encoding failed"`) and
`toml-encoding-error-path` (default `nil`).

See also: [TOML encoding error](conditions.md#toml-encoding-error).

### `toml-encoding-error-message`

Return a bounded description of the failure; defaults to
`"TOML encoding failed"`.

**Signals**: `none`.

See also: [TOML encoding error](conditions.md#toml-encoding-error).

### `toml-encoding-error-path`

Return the path from the root table to the offending value, or `nil`.

**Signals**: `none`.

See also: [TOML encoding error](conditions.md#toml-encoding-error).
