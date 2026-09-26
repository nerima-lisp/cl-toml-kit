# Data model

The reader and writer share a native Common Lisp value model. Primitive TOML
values are not wrapped in adapter structs.

| TOML | Lisp representation |
| --- | --- |
| table | `hash-table` with `:test 'equal` and string keys |
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
arrays must be vectors. Tables are inserted in source order. The writer uses
SBCL's insertion-order `maphash` traversal, and this behavior is covered by
tests.
