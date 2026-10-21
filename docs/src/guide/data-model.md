# Data Model and Mapping

The reader and the writer share one native Common Lisp value model. TOML
values map directly onto existing Common Lisp types, so there are no wrapper
structs and no conversion step between reading and writing.

## Mapping table

| TOML | Lisp representation |
| --- | --- |
| table | hash table with test `equal` |
| array, including an array of tables | `simple-vector` |
| string | `string` |
| integer | signed 64-bit `integer` |
| float | `double-float`, including SBCL infinity and NaN |
| true | `t` |
| false | `+toml-false+` |
| offset date-time | `cl-date-kit:offset-date-time` |
| local date-time | `cl-date-kit:local-date-time` |
| local date | `cl-date-kit:local-date` |
| local time | `cl-date-kit:local-time` |

Every TOML table, whether it comes from a `[table]` header, an inline table,
or an element of an array of tables, is a hash table whose test is `equal`.
Every TOML array is a `simple-vector`, with no distinction between arrays of
values and arrays of tables. The writer rejects Lisp types outside this model.

The value specification table in `src/data.lisp` defines the `toml-value`
type, `toml-value-p`, `toml-value-kind`, and the exported per-kind types and
predicates. `toml-value-typecase` uses the same table to expand a `typecase`
and rejects unknown kind keywords at macro expansion. See the
[API reference](../reference/api.md) for the exported symbols.

## Opaque TOML false

TOML false is not `nil`. Common Lisp uses `nil` for both boolean false and the
empty list, and in this model `nil` and lists are not TOML values at all: an
empty TOML array is an empty `simple-vector`, and TOML has no null. If `nil`
doubled as TOML false, the empty list and the empty array would collide, which
is exactly the ambiguity this model avoids.

TOML false is instead an opaque sentinel, `+toml-false+`. It is a single
object, distinct from both `t` and `nil`, created only by the library. Test
for it with `toml-false-p`, which compares by identity:

```lisp
(cl-toml-kit:toml-false-p cl-toml-kit:+toml-false+) ; => T
(cl-toml-kit:toml-false-p nil)                      ; => NIL
(cl-toml-kit:toml-false-p t)                        ; => NIL
```

The printed form of `+toml-false+` is unspecified. Do not match on how it
prints, and do not round-trip it through `prin1` and a reader; use
`toml-false-p`.

There is no TOML null. To represent no value, omit the key from the table.

## Table key order

The reader inserts keys in source order. The writer visits each table in
SBCL's `maphash` order, but groups entries into values, tables, and arrays of
tables in that order. Insertion order is retained within each group, while a
parse-encode round trip can move keys across groups.

This relies on SBCL's insertion-order hash-table traversal, which is not a
portable Common Lisp guarantee. The test suite checks representative output
ordering. If your code depends on key order, keep this scope in mind.

## Date and time values

TOML has no date-time value with a named time zone and no standalone offset-time
value. The other cl-date-kit types therefore never appear in a TOML document.

`cl-toml-kit` does not re-export these type names. Use the `cl-date-kit:`
prefix to refer to them, or import them from `cl-date-kit` into your package.
The examples on this site use the prefix.

For construction and arithmetic, see the
[cl-date-kit documentation](https://nerima-lisp.github.io/cl-date-kit/).

## Integers

TOML integers are signed 64-bit. The Lisp type is exactly `(signed-byte 64)`,
also available under the name `toml-integer`, with the matching
`toml-integer-p` predicate.

The writer accepts integers from `-9223372036854775808` (`-2^63`) through
`9223372036854775807` (`2^63-1`). An integer outside that range signals
`toml-encoding-error` when encoded; see
[Writing TOML](writer.md#errors).

## Floats

A TOML float is a `double-float`, with no support for `single-float`. The
full TOML float range is available: SBCL infinity and NaN are `double-float`
values, recognizable with `sb-ext:float-infinity-p` and
`sb-ext:float-nan-p`, and the writer prints them as `inf`, `-inf`, and `nan`.

Negative zero is preserved: `-0.0d0` encodes as `-0.0`, not `0.0`.
