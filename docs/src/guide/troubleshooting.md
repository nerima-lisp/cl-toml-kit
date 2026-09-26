# Troubleshooting

Symptom, cause, and remedy for the points that come up once you go past the
examples in [Getting Started](../getting-started.md). For how the writer
decides each output, see [Writing TOML](writer.md); for the value model, see
[Data Model and Mapping](data-model.md).

## nil is not TOML false

**Symptom**: you set a key to `nil` expecting `key = false`, and `encode`
signals `toml-encoding-error` about an unsupported value.

**Cause**: `nil` is both boolean false and the empty list in Common Lisp, and
in this model `nil` and lists are not TOML values. An empty TOML array is an
empty `simple-vector`, and TOML false is the opaque sentinel `+toml-false+`.

**Remedy**: use `+toml-false+` for false and recognize it with
`toml-false-p`. There is no TOML null; to express "no value", omit the key
from the hash table. See [Opaque TOML false](data-model.md#opaque-toml-false).

## Why does encoding reject my hash table

**Symptom**: `encode` signals `toml-encoding-error` with "Table must use the
EQUAL hash-table test", or with the top-level message.

**Cause**: `make-hash-table` defaults to test `eql`. TOML tables are `equal`
hash tables, and the writer checks the test of every table it writes,
including the top level. A top-level value that is not a hash table at all is
rejected first.

**Remedy**: create every table with `(make-hash-table :test 'equal)`. The
condition's accessors are listed in
[Conditions](../reference/conditions.md#toml-encoding-error).

## Why is my key written as a quoted string

**Symptom**: a key such as `"my key"` or `"a.b"` appears quoted in the output,
or an empty key becomes `""`.

**Cause**: bare keys are limited to the ASCII characters `A-Z`, `a-z`, `0-9`,
`-`, and `_`. Any other key, including the empty string, is written as a basic
string.

**Remedy**: nothing to fix. Quoted keys are valid TOML and parse back to the
same string. If you want the bare form, rename the key so it uses only
bare-key characters. See [Keys](writer.md#keys).

## Why does encoding reject my integer

**Symptom**: `encode` signals `toml-encoding-error` with "Integer is outside
TOML's signed 64-bit range".

**Cause**: TOML integers are signed 64-bit. Values below
`-9223372036854775808` or above `9223372036854775807` do not exist in TOML.
`(ash 1 63)` is the first integer beyond the range, and larger bignums are
caught the same way.

**Remedy**: keep integers inside the range, or store the value as a string if
your application needs larger numbers. See
[Integers](data-model.md#integers).

## Why is my nested table written inline

**Symptom**: a table you expected as a `[path]` section appears as
`{ key = value }` inside a line.

**Cause**: headers exist only for table entries. A table reached as a value,
meaning an array element or an entry of an inline table, is written inline
because there is nowhere to put a header for it. At table level, arrays of
tables take `[[path]]` headers instead, so the arrays you see inline are
arrays that are themselves values.

**Remedy**: if a table should get its own section, store it as an entry of a
parent hash table, not as an element of a vector. See
[Output shape](writer.md#output-shape).

## Why does the output order change between runs

**Symptom**: the same logical table sometimes encodes with its keys in a
different order.

**Cause**: the writer emits entries in SBCL's `maphash` traversal order, which
is insertion order for tables whose keys are only ever added. It also groups
entries into three passes: value entries first, then tables, then arrays of
tables. Rebuilding a table with a different insertion order, or building it by
iterating another structure, changes the output order.

**Remedy**: insert keys in the order you want them emitted. Treat the order as
an SBCL behavior fixed by tests, not a portable guarantee; see
[Table key order](data-model.md#table-key-order).

## Date and time values must be cl-date-kit objects

**Symptom**: encoding a universal time, a string such as
`"2024-01-02T03:04:05Z"`, or a list of date parts signals
`toml-encoding-error`.

**Cause**: the four TOML temporal kinds are the cl-date-kit types
`offset-date-time`, `local-date-time`, `local-date`, and `local-time`, used
directly with no adapter structs. A string is a string, not a date.

**Remedy**: construct the matching cl-date-kit object. See
[Date and time values](data-model.md#date-and-time-values) and the
[cl-date-kit documentation](https://nerima-lisp.github.io/cl-date-kit/).

## Is cl-toml-kit thread-safe

Independent calls over independent data need no external locking. `encode`
works through a local `with-output-to-string` stream that only that call sees,
and the writer keeps no global mutable state: its character-class and escape
tables are initialized once and only read afterwards.

What you must synchronize yourself:

- A stream shared across threads. `write-toml` writes to whatever stream you
  pass it; concurrent writes to one stream are your responsibility, as with
  any other library.
- A hash table shared across threads. The writer adds no locking around your
  data; if two threads mutate or encode the same table concurrently, ordinary
  Common Lisp concurrency rules apply.

The reader is covered by the same contract: `parse` and `parse-file` are plain
functions that return a value or signal a condition, with parser state
confined to the call. The reader implementation is developed separately, and
this page does not inspect its internals, so treat that statement as the
documented contract rather than a verified one.

## SBCL only

`cl-toml-kit` is SBCL only. The source uses
`sb-ext:define-load-time-global` for the false sentinel and
`sb-ext:float-infinity-p` and `sb-ext:float-nan-p` for the float special
cases, and the output order relies on SBCL's insertion-order hash-table
traversal (see [Table key order](data-model.md#table-key-order)). Do not
expect it to load or behave the same on other implementations.
