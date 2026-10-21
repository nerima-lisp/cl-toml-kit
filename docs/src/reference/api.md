# API Reference

`cl-toml-kit` exports reader and writer entry points, format-preserving byte
editing and source-scanning functions, native values and value-model
operations, shared processing limits, and structured conditions with their
readers. TOML date and time values use types from `cl-date-kit`, which this
package does not re-export. These are all the `cl-toml-kit` exports.

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

Parse a TOML document.

| Argument | Type | Default | Meaning |
| --- | --- | --- | --- |
| `source` | `string` or `character input stream` | n/a | The TOML document, as a string or a character input stream. |
| `source-name` | any value | `nil` | Optional label for parse errors. Pathnames use namestring; other values become diagnostic text. The result is control-escaped and capped at 256 characters. |

**Returns**: the top-level table, a hash table with `:test 'equal`. Keys and
values use the [native value mapping](../guide/data-model.md).

**Signals**: `toml-parse-error` for malformed TOML or an input-limit error.

**Example**:

```lisp
(let ((table (cl-toml-kit:parse
              "title = \"TOML\"
count = 2")))
  (list (gethash "title" table)
        (gethash "count" table)))
;; => ("TOML" 2)
```

See also: [Reader](../guide/reader.md), [Conditions](conditions.md#toml-parse-error).

### `parse-file`

```lisp
(cl-toml-kit:parse-file pathname)
  => hash-table
```

Read the file at `pathname`, a pathname designator, and parse its contents as
one TOML document. For parse errors, `parse-file` supplies the pathname's
namestring as `source-name`.

**Returns**: the top-level table, a hash table with `:test 'equal`.

**Signals**: `toml-parse-error` for malformed TOML, an input-limit error, or
invalid UTF-8. The usual file conditions (for example `file-error`) apply when
the file cannot be read.

**Example**:

```lisp
(cl-toml-kit:parse-file #p"config.toml")
```

See also: [Reader](../guide/reader.md).

### `encode`

```lisp
(cl-toml-kit:encode value)
  => string
```

Serialize `value` to a TOML document and return it as a string. `value` is
the top-level table, an `equal` hash table whose keys are strings.

**Signals**: `toml-encoding-error` for an invalid top level, non-string keys,
out-of-range integers, or unsupported values.

**Example**:

```lisp
(cl-toml-kit:encode
 (let ((table (make-hash-table :test 'equal)))
   (setf (gethash "title" table) "TOML")
   table))
;; TOML output (the returned string ends with a newline):
;; title = "TOML"
```

See also: [Writer](../guide/writer.md), [Conditions](conditions.md#toml-encoding-error).

### `write-toml`

```lisp
(cl-toml-kit:write-toml value stream)
  => value
```

Write `value` as TOML text to the character `stream` and return the original
`value`. The stream is left open.

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
;; TOML output (the returned string ends with a newline):
;; n = 1
```

See also: [Writer](../guide/writer.md).

## Format-preserving editing

### `edit-toml`

```lisp
(cl-toml-kit:edit-toml source path &optional new-value &key delete)
  => octet-vector
```

Edit a UTF-8 TOML document represented by a vector of unsigned-byte 8 values.
`path` is a string key or a sequence of string keys and zero-based non-negative
array indices. A string component is one key, so dots in a string key are not
path separators; use multiple components for a nested path. Existing values
are replaced when `new-value` is supplied. Use `:delete t` with `new-value`
set to `nil`, or use `delete-toml`, to remove an existing value. If both
`new-value` and `:delete t` are omitted, `toml-format-preservation-error` is
signaled. Bytes outside the edited span, including the BOM, comments, key
order, whitespace, line endings, and string delimiters, are retained.

```lisp
(cl-toml-kit:edit-toml source path nil :delete t)
```

```lisp
(cl-toml-kit:edit-toml
 (make-array 22 :element-type '(unsigned-byte 8)
                 :initial-contents
                 '(110 97 109 101 32 61 32 34 111 108 100 34 32 32
                   35 32 107 101 101 112 13 10))
 '("name")
 "new")
;; Result: UTF-8 bytes for this TOML line, ending with CRLF:
;; name = "new"  # keep
```

Adding a missing table entry writes a TOML-formatted key path with ` = ` and
uses the surrounding line ending. To append to an existing array, use its
current length as the final path index; for example, `("items" 2)` appends to
`items = [1, 2]`. Array-of-tables elements must be selected with an integer
path component, such as `("products" 1 "name")`; an edit that leaves the
element ambiguous signals `toml-format-preservation-error`.
Adding `("server" "port")` when the source already has
`server.host = "example"` is also rejected because it would extend a parent
created by a dotted-key assignment.

After an edit, `edit-toml` parses the edited bytes and compares the resulting
document with a copy of the original parsed document after applying the
requested replacement, insertion, or deletion to that copy at `path`; a
mismatch signals `toml-format-preservation-error`.
`edit-toml` signals `toml-encoding-error` when a replacement or added value
contains surrogate code points or exceeds `*toml-max-nesting-depth*`. When
adding a table entry, a key containing a surrogate code point also signals
`toml-encoding-error`.

Deletion is rejected when the removed span contains `#` or the immediately
preceding line is a comment, because the comment ownership cannot be retained.
Array insertion is rejected when a trailing element comment would be crossed.
When adding to a table, trailing blank and comment lines remain after the new
assignment. Unsupported structural edits are rejected rather than returning
parseable bytes with a changed meaning.

### `delete-toml`

```lisp
(cl-toml-kit:delete-toml source path)
  => octet-vector
```

Delete the value at `path` from the UTF-8 byte vector `source`. This is
equivalent to `(edit-toml source path nil :delete t)`. The input vector is not
modified.

## Native Values

### `+toml-false+`

The opaque sentinel that represents TOML `false`. It is a load-time global,
not a constant, and it is not `nil`. Its identity is what matters, so test for
it with `toml-false-p` rather than depending on its value or printed form.

```lisp
(cl-toml-kit:toml-false-p cl-toml-kit:+toml-false+) ; => t
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

`toml-false-sentinel` is the unexported type of `+toml-false+`. The
`toml-value` type includes any `hash-table`, regardless of its test, but
`toml-value-p` and `toml-value-kind` recognize a table as a native TOML value
only when its hash-table test is `equal` (see `toml-table-p`).

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

Unknown kind keywords signal `toml-value-model-error` during macro expansion.
At runtime, a `:table` clause checks that its hash table uses the `equal` test.
If it does not, the `t` clause runs when present; without one, the macro
signals `toml-encoding-error` with the message `Invalid TOML table`. For any
other unmatched kind, the `t` clause also runs when present; without one, the
macro signals `toml-encoding-error` with the message `Not a TOML value`.

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

## Shared processing limits

These dynamically bindable special variables provide limits to operations
that consult them. Such an operation requires the bound value to be a
non-negative integer and uses the smaller of that value and the hard ceiling;
it does not modify the binding. An invalid binding signals `type-error`, and
an input exceeding the effective limit signals that operation's error
condition.

| Variable | Default | Hard ceiling | Current enforcement | Condition when exceeded |
| --- | ---: | ---: | --- | --- |
| `*toml-max-nesting-depth*` | `256` | `1024` | `parse` and `parse-file` limit array and inline-table nesting plus dotted-key and table-header paths, including array-of-tables headers. `edit-toml` applies the limit to its source and replacement or added values. `encode` and `write-toml` limit nested tables and arrays. | `toml-parse-error` for `parse` and `parse-file`; `toml-format-preservation-error` for edit source or result limits; `toml-encoding-error` when encoding values. |
| `*toml-max-input-bytes*` | `16777216` | `1073741824` | `parse-file` checks known file sizes before allocation; for unknown sizes, it reads incrementally through at most the effective limit plus one byte and rejects excess before decoding. `edit-toml` checks octet-vector length before decoding. | `toml-parse-error` for `parse-file`; `toml-format-preservation-error` for `edit-toml`. |
| `*toml-max-input-characters*` | `16777216` | `67108864` | Character length for strings and streams passed to `parse`, decoded `parse-file` text, and decoded `edit-toml` text; streams stop after reading the first character over the limit. | `toml-parse-error` for `parse` and `parse-file`; `toml-format-preservation-error` for `edit-toml`. |
| `*toml-max-number-token-length*` | `256` | `4096` | `parse` and `parse-file` limit integer and finite floating-point tokens; `edit-toml` applies the reader check to its source and edited result. Infinity and NaN tokens bypass the limit. | `toml-parse-error` while parsing; `toml-format-preservation-error` if edited-result validation exceeds the limit. |
| `*toml-max-path-components*` | `1024` | `4096` | Number of components in an editor path. Dotted keys and table headers can make a path longer than its nesting depth. | `toml-format-preservation-error` while editing. |
| `*toml-max-tables*` | `16384` | `32768` | Maximum tables created during one parse, including the root, dotted-key paths, table headers, array-of-tables headers, and inline tables. `edit-toml` applies it while parsing its source and validating the edited result. | `toml-parse-error` while parsing or reading the edit source; `toml-format-preservation-error` if edited-result validation exceeds the limit. |

For `edit-toml`, replacement values and array or inline-table additions start
at their parent depth; table-entry additions start at depth zero.

## Conditions

The condition hierarchy is documented in full in
[Conditions](conditions.md); the entries here list the exported types and
accessors only.

### `toml-kit-error`

A condition, subtype of `error`. It is the base of the library-defined error
conditions and carries no slots.

See also: [The shared base condition](conditions.md#the-shared-base-condition).

### `toml-value-model-error`

A condition, subtype of `toml-kit-error`, signalled during macro expansion
when `toml-value-typecase` contains an unknown kind keyword. Its reader is
`toml-value-model-error-message`.

See also: [TOML value model error](conditions.md#toml-value-model-error).

### `toml-value-model-error-message`

Return the message describing the invalid TOML value kind.
See also: [TOML value model error](conditions.md#toml-value-model-error).

### `toml-parse-error`

A condition, subtype of `toml-kit-error`, signalled for malformed TOML,
input-limit errors from `parse` or `parse-file`, and invalid UTF-8 from
`parse-file`.
Its readers, with their default values: `toml-parse-error-source-name`
(`nil`), `toml-parse-error-position` (`0`), `toml-parse-error-line` (`1`),
`toml-parse-error-column` (`1`), `toml-parse-error-path` (`nil`),
`toml-parse-error-expected` (`nil`), `toml-parse-error-context` (`"TOML"`),
and `toml-parse-error-text` (`""`).

See also: [TOML parse error](conditions.md#toml-parse-error).

### `toml-parse-error-source-name`

Return `nil` when no source name is supplied. Otherwise, return bounded,
sanitized diagnostic text derived from `source-name`.
See also: [TOML parse error](conditions.md#toml-parse-error).

### `toml-parse-error-position`

Return the zero-based character offset where TOML parsing failed. For a
`parse-file` byte-limit error, return `0`; for a UTF-8 decoding error, return
the byte offset in the file.
See also: [TOML parse error](conditions.md#toml-parse-error).

### `toml-parse-error-line`

Return the one-based line number where parsing failed, or `nil` when a byte or
character input-size limit is exceeded before TOML parsing.
See also: [TOML parse error](conditions.md#toml-parse-error).

### `toml-parse-error-column`

Return the one-based column number where parsing failed, or `nil` when a byte
or character input-size limit is exceeded before TOML parsing.
See also: [TOML parse error](conditions.md#toml-parse-error).

### `toml-parse-error-path`

Return the path of table keys and vector indices to the failure, or `nil`.
See also: [TOML parse error](conditions.md#toml-parse-error).

### `toml-parse-error-expected`

Return a short description of what the parser expected, or `nil`.
See also: [TOML parse error](conditions.md#toml-parse-error).

### `toml-parse-error-context`

Return the context label of the failure; defaults to `"TOML"`.
See also: [TOML parse error](conditions.md#toml-parse-error).

### `toml-parse-error-text`

Return a bounded, sanitized snippet of the input near the failure.
See also: [TOML parse error](conditions.md#toml-parse-error).

### `toml-encoding-error`

A condition, subtype of `toml-kit-error`, signalled by the writer for values
that cannot be represented in TOML. Its readers are
`toml-encoding-error-message` (default `"TOML encoding failed"`) and
`toml-encoding-error-path` (default `nil`).

See also: [TOML encoding error](conditions.md#toml-encoding-error).

### `toml-encoding-error-message`

Return a bounded failure description; defaults to `"TOML encoding failed"`.
See also: [TOML encoding error](conditions.md#toml-encoding-error).

### `toml-encoding-error-path`

Return the path from the root table to the offending value, or `nil`.
See also: [TOML encoding error](conditions.md#toml-encoding-error).

### `toml-format-preservation-error`

A condition, subtype of `toml-kit-error`, signalled when an edit cannot
preserve unrelated source bytes safely. Its readers are
`toml-format-preservation-error-message` and
`toml-format-preservation-error-path`.

See also: [`toml-format-preservation-error`](conditions.md#toml-format-preservation-error).

### `toml-format-preservation-error-message`

Return the reason the format-preserving edit was rejected.
See also: [`toml-format-preservation-error`](conditions.md#toml-format-preservation-error).

### `toml-format-preservation-error-path`

Return the requested logical path, or `nil` when no path applies.
See also: [`toml-format-preservation-error`](conditions.md#toml-format-preservation-error).

## Source scanning

### `toml-comment-spans`

```lisp
(cl-toml-kit:toml-comment-spans source)
  => list of conses
```

Return source-ordered `(start . end)` character-offset pairs for comments.
Each span includes the leading `#`, uses an inclusive start and exclusive end,
and excludes the line ending. Comment marks inside quoted strings are not
included.

**Signals**: `type-error` when `source` is not a string.
