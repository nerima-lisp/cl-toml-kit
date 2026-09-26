# Architecture

`cl-toml-kit` splits into a foundation shared by both directions, a reader
layer, and a writer layer. The full implementation contract lives in the
repository's [design document](https://github.com/nerima-lisp/cl-toml-kit/blob/main/docs/design/architecture.md).

## Module layout

ASDF loads `src/package.lisp`, `src/conditions.lisp`, and `src/data.lisp`
first, then the writer files (`src/writer-data.lisp`, `src/writer-macros.lisp`,
`src/writer.lisp`). The reader adds `src/reader*.lisp`.

The foundation owns the package definition, the conditions, and the value
model in `src/data.lisp`. Reader and writer share the value and condition
contracts but do not use each other's private helpers, so either layer can
change without disturbing the other.

## Native value contract

The reader returns and the writer accepts the same set of Lisp values. TOML
tables are hash tables with `:test 'equal`, arrays are simple vectors, and
the four date kinds are `cl-date-kit` objects. `+toml-false+` represents TOML
false, and `nil` and lists are not TOML values. See [the data
model](../guide/data-model.md) for the full mapping.

Table recognition is O(1): it checks only that a value is a hash table whose
test is `equal`. The writer validates that each key is a string when it emits
the key, not when the value is constructed.

## Conditions

`toml-kit-error` is the root condition. `toml-parse-error` reports malformed
input with position, line, column, and path information; `toml-encoding-error`
reports values that cannot be represented in TOML. Both derive from the root
and both define `:report`. See [Conditions](../reference/conditions.md) for
the exported accessors.

## Reader

The reader implementation is in progress; this section describes the contract
it builds against. `parse` accepts a string or a character input stream and
returns the top-level table, or signals `toml-parse-error`. Internally, the
grammar and token code may use continuations to propagate success, failure,
and source location, but `parse` remains an ordinary function. Input is
normalized to a `simple-string` and scanned by index. See
[Reader](../guide/reader.md) for usage.

## Writer

The writer emits TOML directly to the caller's stream. `write-toml` is the
streaming entry point and `encode` is its string-output wrapper.

```lisp
(cl-toml-kit:write-toml value stream)
(cl-toml-kit:encode value)
```

Value dispatch and the output shape both derive from the declarative tables in
`src/data.lisp` and `src/writer-data.lisp`: the emitter macro walks the table
and expands to one `typecase`. See [Writer](../guide/writer.md) for usage.

## Performance policy

The implementation targets linear work in input length. It is SBCL only and
does not use `(safety 0)`. Containers are hash tables and simple vectors, so
lookup and append never degrade to quadratic list construction.

## Tests

The cl-weave specs cover every value kind, the false sentinel, 64-bit integer
boundaries, invalid `nil` and list values, date object identity, and insertion
order. Reader tests cover conformance fixtures and source streams. Writer
tests cover direct streams, unsupported values, and round trips. The canonical
gate is:

```console
timeout 1800 nix flake check
```
