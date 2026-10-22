# Changelog

## 0.3.0

### Breaking changes

- The public byte-oriented alias `edit-toml-bytes` has been removed. Replace it with `edit-toml`, which takes a UTF-8 byte-vector `source`, a `path` that is a string key or a sequence of string keys and zero-based array indices, and an optional native TOML `new-value`. For deletion, call `(edit-toml source path nil :delete t)`.
- Parsing `-0.0` now preserves its sign as negative zero.
- Parse error columns now report the one-based column where parsing failed.
- New default processing limits can reject documents or edits that earlier versions accepted. See Security for the limits and conditions.

### Security

The library exports six dynamically bindable limits, each initialized to the listed default. Operations that consult a limit require its current value to be a non-negative integer and enforce the lower of that value and the hard ceiling without changing the binding. An invalid value signals `type-error`.

| Limit | Default | Hard ceiling | Condition when exceeded |
| --- | ---: | ---: | --- |
| `*toml-max-nesting-depth*` | 256 levels | 1,024 levels | `toml-parse-error` while parsing, `toml-format-preservation-error` while editing, and `toml-encoding-error` while writing. |
| `*toml-max-input-bytes*` | 16,777,216 bytes | 1,073,741,824 bytes | `toml-parse-error` for `parse-file`; `toml-format-preservation-error` for `edit-toml`. |
| `*toml-max-input-characters*` | 16,777,216 characters | 67,108,864 characters | `toml-parse-error` for `parse` and `parse-file`; `toml-format-preservation-error` for `edit-toml`. |
| `*toml-max-number-token-length*` | 256 characters | 4,096 characters | `toml-parse-error` while parsing; `toml-format-preservation-error` during edit validation. |
| `*toml-max-path-components*` | 1,024 components | 4,096 components | `toml-format-preservation-error` while editing. |
| `*toml-max-tables*` | 16,384 tables | 32,768 tables | `toml-parse-error` while parsing; `toml-format-preservation-error` while editing. |

The number-token limit applies to integers and finite floating-point tokens. Infinity and NaN tokens are exempt. `parse-file` input and the `edit-toml` byte-vector source are checked before decoding; decoded file text is also subject to the character limit. Character streams passed to `parse` signal `toml-parse-error` when they contain a character beyond the limit.

Parsing checks nesting in arrays, inline tables, dotted keys, and table headers, including array-of-tables headers. The writer rejects cycles and excessive nesting with `toml-encoding-error`. Dotted-key paths are checked one component at a time, avoiding repeated scans of earlier components and quadratic work on long paths. The table limit counts each table created during parsing, including the root, tables created for dotted keys and headers, array-of-tables entries, and inline tables.

Diagnostics escape control characters and surrogate code points. Source-name labels in diagnostic messages are truncated at 256 rendered characters. The reader rejects Unicode escapes that designate surrogate values. The writer rejects surrogate code points in strings and keys; the editor rejects them in replacement or added values and in added keys.

### Performance

The continuation-based reader trades parsing throughput for the security improvements in this release.

For flat TOML inputs, an allocation optimization brought the continuation-based reader's allocations closer to those of the earlier parser.

### Dependencies and build

UTF-8 decoding in the reader and UTF-8 encoding and decoding in `edit-toml` now use `cl-codec-kit` 0.6.0. The runtime requires minimum versions of `cl-parser-kit` 1.1.1, `cl-date-kit` 1.2.0, and `cl-codec-kit` 0.6.0. The test system requires `cl-weave` 1.4.0 and `cl-json-kit` 1.2.0.

### Testing

Property tests generate TOML documents and check parsing, writing, round trips, and edits. Fuzz cases cover long inputs, deeply nested values, dotted-key boundaries, arbitrary byte inputs, and mutations of valid TOML bytes. Writer mutation tests require all 16 generated mutants to be killed, with no survivors, errors, or timeouts. Coverage checks enforce the expression and branch floors listed for each source file in `scripts/run-coverage.lisp` and require at least 90% for both aggregate measures.
