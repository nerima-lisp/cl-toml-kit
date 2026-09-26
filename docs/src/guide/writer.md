# Writer

`encode` returns TOML text, and `write-toml` writes the same representation to
a character stream. Both accept a top-level `equal` hash table whose keys are
strings. Tables, vectors, strings, signed 64-bit integers, double floats,
`t`, `+toml-false+`, and the four cl-date-kit date types are supported.

Scalar entries are emitted first in hash-table traversal order. Non-empty
tables follow as `[path]` headers, and non-empty vectors containing only
tables follow as repeated `[[path]]` headers. Other vectors and empty tables
are inline values. Keys use bare-key syntax when possible and basic strings
otherwise. Strings escape control characters, quotes, and backslashes.

Invalid values signal `toml-encoding-error`. Its `toml-encoding-error-path`
accessor contains the path from the root table, including vector indexes.
`write-toml` writes directly to the supplied stream; only `encode` allocates
the output string.
