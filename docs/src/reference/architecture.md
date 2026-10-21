# Architecture

`cl-toml-kit` provides a TOML reader, writer, and format-preserving editor.
See the [design document](https://github.com/nerima-lisp/cl-toml-kit/blob/main/docs/design/architecture.md)
for reader, writer, and editor design details.

## Module layout

The `cl-toml-kit` ASDF system loads these source components serially in this
order:

```text
src/package.lisp
src/syntax-data.lisp
src/limits.lisp
src/comment-scan.lisp
src/conditions.lisp
src/data.lisp
src/reader-data.lisp
src/reader-macros.lisp
src/reader-scan.lisp
src/reader-path.lisp
src/reader-strings.lisp
src/reader-numbers.lisp
src/reader-values.lisp
src/reader-document.lisp
src/writer-data.lisp
src/writer-macros.lisp
src/writer.lisp
src/reader.lisp
src/edit-model.lisp
src/edit-scan.lisp
src/edit-document.lisp
src/edit-bytes.lisp
src/edit-semantic.lisp
src/edit-splice.lisp
src/edit.lisp
```

The `cl-toml-kit/benchmark` ASDF system loads `benchmark/runner.lisp` and
`benchmark/cases.lisp`.

The `src/reader*.lisp` components parse TOML, the `src/writer*.lisp` components
emit it, and the `src/edit*.lisp` components map source spans, validate edits,
and splice changed bytes.

See [Data Model and Mapping](../guide/data-model.md) for value representations,
[Reader](../guide/reader.md) and [Writer](../guide/writer.md) for their public
interfaces, and [Conditions](../reference/conditions.md) for error details.

## Format-preserving editor

`edit-toml` scans a UTF-8 byte vector into source spans, then replaces or deletes
existing values and inserts new values at a path. It checks that the edited
document matches the requested change and preserves unselected bytes. It
supports scalar assignments, inline tables, arrays, table sections, and indexed
array-of-tables values. It signals `toml-format-preservation-error` when a
structural edit has ambiguous source ownership. See the
[edit-toml API](../reference/api.md#edit-toml) for the byte-vector, path, and
replacement contract, and [Conditions](../reference/conditions.md) for failure
cases.

## Processing limits

See [Shared processing limits](api.md#shared-processing-limits) in the API
reference for the defaults, hard ceilings, and enforcement details.

## Tests

The `cl-toml-kit/test` ASDF system loads these components serially in this
order:

```text
t/package.lisp
t/limits-test.lisp
t/helpers-values.lisp
t/helpers-values-test.lisp
t/helpers-edit.lisp
t/helpers-edit-test.lisp
t/conditions-test.lisp
t/data-test.lisp
t/writer-test.lisp
t/writer-property-test.lisp
t/fixture-toml-test.lisp
t/reader-values-test.lisp
t/comment-scan-test.lisp
t/reader-document-test.lisp
t/reader-errors-test.lisp
t/reader-property-test.lisp
t/roundtrip-test.lisp
t/roundtrip-property-test.lisp
t/reader-conformance-test.lisp
t/edit-replacement-test.lisp
t/edit-path-security-test.lisp
t/edit-input-limits-test.lisp
t/edit-nesting-security-test.lisp
t/edit-splice-test.lisp
t/edit-document-boundaries-test.lisp
t/edit-scan-boundaries-test.lisp
t/edit-splice-boundaries-test.lisp
t/reader-nesting-security-test.lisp
t/reader-number-security-test.lisp
t/reader-input-security-test.lisp
t/edit-semantic-boundaries-test.lisp
```
