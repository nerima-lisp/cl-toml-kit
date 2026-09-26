# Architecture

This document is the implementation contract for the TOML 1.1.0 reader and
writer. The reader returns the values described here and the writer accepts
those same values.

## Ownership and layout

The foundation owns `src/package.lisp`, `src/conditions.lisp`,
`src/data.lisp`, `src/model.lisp`, and their tests. Reader owns
`src/reader*.lisp` and `t/reader*-test.lisp`. Writer owns `src/writer*.lisp`
and `t/writer*-test.lisp`. Reader owns the shared fixture loaders in
`t/fixture-*.lisp`; neither stream edits `t/fixtures/`.

ASDF loads package, conditions, data, model, then reader and writer files.
Reader and Writer use the common value and condition contracts but do not use
each other's private helpers.

## Public API

The public operations are ordinary functions:

```lisp
(parse source &key source-name)
(parse-file pathname)
(encode value)
(write-toml value stream)
```

`source` is a string or character input stream. `parse` returns the top-level
hash table. `encode` returns a string, while `write-toml` writes directly to a
character stream. Invalid input and unsupported values signal the documented
conditions. `+toml-false+` and `toml-false-p` represent TOML false.

## Native value contract

| TOML | Lisp value |
| --- | --- |
| table, inline table, or table-array element | hash table, equal test, string keys |
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

`nil` and lists are not TOML values. The writer signals
`toml-encoding-error` for them. Date values are the required cl-date-kit
objects directly; there are no adapter structs and TOML has no zoned date-time
or offset-time value.

Reader inserts table keys in source order and never removes them. Writer uses
`maphash` order. This project intentionally relies on SBCL's insertion-order
hash-table traversal and fixes that property with tests; it is not a portable
hash-table guarantee.

The value declarations in `src/data.lisp` are data. Macros derive the native
type declarations and value dispatch from that table. They must not introduce
wrapper objects or duplicate public aliases.

## Conditions

`toml-kit-error` is the root condition. `toml-parse-error` adds source name,
position, line, column, path, expected token, context, and text. Each slot has
its exported reader. `toml-encoding-error` adds message and path. Both
concrete conditions define `:report`; callers should inspect accessors rather
than parse report strings.

## CPS and macros

Reader grammar and token code may use CPS for success, failure, and source
location propagation. CPS is an internal implementation detail: the public
reader remains a function that returns a value or signals a condition. Writer
may use a continuation around direct stream writes. Hot continuations should
be `dynamic-extent` or expanded inline so parsing and writing do not allocate
one closure per character.

Macros generate declarations and repetitive dispatch only. Public operations,
condition construction, and I/O remain functions.

## Performance policy

The implementation targets linear work in input length. It is SBCL-only and
must not use `(safety 0)` or a partial `declaim (optimize ...)`; optimization
declarations, when needed, specify the complete project policy. Reader input
is normalized to `simple-string` and scanned by index. Character classes are
data tables, and scanners do not build intermediate substrings. Writer emits
directly to the supplied stream; `encode` is the string-output convenience
wrapper around that path.

Containers are hash tables and simple vectors so lookup and append do not
degrade to alist/list quadratic construction. Benchmarks in `benchmark/` are
diagnostic only and never decide merges.

## Tests and verification

cl-weave tests cover every value kind, false sentinel, 64-bit boundaries,
invalid nil/list values, date object identity, insertion order, and every
condition report and accessor. Reader tests cover conformance fixtures and
source streams. Writer tests cover direct streams, unsupported values, and
round trips. Coverage is measured by cl-weave and the foundation target is
100%.

The canonical repository gate is `timeout 1800 nix flake check`. The benchmark
workflow is separate, has a timeout, and is diagnostic rather than a merge
gate.
