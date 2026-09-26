# Data Model and Mapping

The reader and the writer share one native Common Lisp value model. TOML
values map directly onto existing Common Lisp types, so there are no wrapper
structs and no conversion step between reading and writing. The table below is
the whole model.

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
values and arrays of tables. `nil` and lists are not TOML values, so anything
not listed in the table is rejected.

The union of these types is the `toml-value` type. `toml-value-p`,
`toml-value-kind`, and the per-kind predicates are all derived from one
specification table in `src/data.lisp`; see the
[API reference](../reference/api.md) for them.

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

There is no TOML null. A key that has no value is simply absent from the hash
table.

## Table key order

The reader inserts keys in source order and never removes them. The writer
emits entries in the order SBCL's `maphash` visits them. Together these mean a
parse-encode round trip preserves the order of the keys in the document you
read.

This is an intentional reliance on SBCL's insertion-order hash-table
traversal. It is not a portable Common Lisp guarantee: other implementations
may visit hash-table entries in any order. The behavior is fixed by the test
suite. If your code depends on key order, keep this scope in mind.

## Date and time values

The four TOML temporal kinds use cl-date-kit types directly. The reader
returns `cl-date-kit:offset-date-time`, `cl-date-kit:local-date-time`,
`cl-date-kit:local-date`, and `cl-date-kit:local-time` objects, and the writer
accepts those same objects; there are no adapter structs in between.

TOML has no zoned date-time and no offset-time value. The other cl-date-kit
types therefore never appear in a TOML document.

`cl-toml-kit` imports the four type names from cl-date-kit for its own use.
That does not make the names available unqualified in your package: if you
want to write `offset-date-time` without the prefix, your own package must
import that symbol from cl-date-kit. The examples on this site always use the
`cl-date-kit:` prefix instead.

This page does not cover how to construct cl-date-kit values. See the
[cl-date-kit documentation](https://nerima-lisp.github.io/cl-date-kit/) for
construction and arithmetic.

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

The value specification table in `src/data.lisp` is the single source of truth
for everything on this page. `define-toml-value-model` expands it into the
`toml-value` type, the value predicates, `toml-value-kind`, and the
`toml-value-typecase` macro. That macro expands to a single `typecase` over the
table, and it rejects unknown kind keywords at macroexpansion time.
