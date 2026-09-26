# Data model

The reader and writer share a native Common Lisp value model. Primitive TOML
values are not wrapped in adapter structs.

| TOML | Lisp representation |
| --- | --- |
| table | `hash-table` with `:test 'equal` |
| array | `simple-vector` |
| string | `string` |
| integer | signed 64-bit `integer` |
| float | `double-float` |
| true | `t` |
| false | `+toml-false+` |
| offset date-time | `cl-date-kit:offset-date-time` |
| local date-time | `cl-date-kit:local-date-time` |
| local date | `cl-date-kit:local-date` |
| local time | `cl-date-kit:local-time` |

Use `toml-false-p` to recognize false. `nil` and lists are not TOML values;
arrays must be vectors. Table recognition checks only the hash-table test and
is O(1); key strings are validated by the writer when it emits each key.
Tables are inserted in source order. The writer uses SBCL's insertion-order
`maphash` traversal, and this behavior is covered by tests.

The value specification table in `src/data.lisp` is the single source of truth
for the `toml-value` type, value predicates, kind dispatch, and
`toml-value-typecase`. The typecase macro expands directly to one Common Lisp
`typecase`; its kind keywords are checked during macro expansion.
