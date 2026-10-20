# Architecture

`cl-toml-kit` provides TOML values, a reader and writer, and a
format-preserving editor. The [design document](https://github.com/nerima-lisp/cl-toml-kit/blob/main/docs/design/architecture.md)
describes the implementation design.

## Module layout

The main ASDF system loads these source components serially in this order:

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

The separate benchmark system loads `benchmark/runner.lisp` and
`benchmark/cases.lisp`.

`src/syntax-data.lisp` defines syntax tables. `src/data.lisp` declares native
value kinds and their type dispatch. `src/reader-data.lisp` defines reader
state and lookup and error tables; `src/writer-data.lisp` defines per-kind
emission forms. The reader modules implement parsing. `src/writer-macros.lisp`
combines the writer forms with `toml-value-typecase`, and `src/writer.lisp`
emits TOML. The editor modules handle paths, scanning, byte mapping, semantic
validation, and splicing.

## Native value contract

The reader returns and the writer accepts the same set of Lisp values. TOML
tables are hash tables with `:test 'equal`, arrays are simple vectors, and
the four date kinds are `cl-date-kit` objects. `+toml-false+` represents TOML
false. `nil` and lists are not TOML values. See [the data
model](../guide/data-model.md) for the full mapping.

Table recognition checks only that a value is a hash table whose test is
`equal`. The writer validates that each table key is a string when it emits
the key.

## Conditions

`toml-kit-error` is the root condition. `toml-parse-error` reports malformed
input with position, line, column, and path information. `toml-encoding-error`
reports values that cannot be represented in TOML. `toml-format-preservation-error`
reports edits that cannot identify a safe source span. All derive from the
root and define `:report`. See [Conditions](../reference/conditions.md) for
the exported accessors.

## Reader

`parse` accepts a string or a character input stream and returns the top-level
table, or signals `toml-parse-error`. `parse-file` decodes UTF-8 bytes and
reports the byte position, line, and column of decoding failures. Reader rules
scan the input as a `simple-string` by character index; the coercion preserves
the input characters.

`define-toml-rule` gives each rule a reader state, starting character index,
success continuation, and failure continuation. On success, a rule calls its
success continuation with the parsed value and next character index. On
failure, it calls the failure continuation with the error index, expected-token
key, and path, which can be `nil`. A failure continuation must not return.
The continuation used by `parse` signals `toml-parse-error`, leaving the
public reader as an ordinary function. See [Reader](../guide/reader.md) for
usage.

## Writer

The writer emits TOML directly to the caller's stream. `write-toml` is the
streaming entry point and `encode` is its string-output wrapper.

```lisp
(cl-toml-kit:write-toml value stream)
(cl-toml-kit:encode value)
```

`src/data.lisp` defines the value-kind dispatch. `src/writer-data.lisp`
supplies an output form for each kind. `define-toml-emitter` combines those
forms with `toml-value-typecase`, which expands to a `typecase`.
See [Writer](../guide/writer.md) for usage.

## Format-preserving editor

`edit-toml` scans a UTF-8 byte vector into source spans. It replaces or deletes
existing values and inserts supported new values. It parses the original and
edited text, checks that the edited result matches the requested value, and
preserves unselected bytes. It supports scalar assignments, inline tables,
arrays, table sections, and indexed array-of-tables values. It signals
`toml-format-preservation-error` when a structural edit has ambiguous source
ownership; see [API](../reference/api.md) and
[Conditions](../reference/conditions.md).

## Processing limits

The package exports five dynamically bindable limit variables. For a variable
used by an operation, the internal `%toml-limit` helper requires a
non-negative integer and caps it at the listed hard ceiling.

| Variable | Default | Hard ceiling | Current enforcement |
| --- | ---: | ---: | --- |
| `*toml-max-nesting-depth*` | 256 | 1,024 | Writer and editor value scanning |
| `*toml-max-input-bytes*` | 16,777,216 | 1,073,741,824 | `edit-toml` input before decoding |
| `*toml-max-input-characters*` | 16,777,216 | 1,073,741,824 | `edit-toml` decoded input |
| `*toml-max-number-token-length*` | 256 | 4,096 | No current consumer; it does not limit reader tokens |
| `*toml-max-path-components*` | 1,024 | 4,096 | `edit-toml` paths |

The reader does not enforce the byte, character, nesting, or number-token
limits. `parse` and `parse-file` do not consult these variables.

## Performance policy

The implementation targets linear work in input length. It is SBCL only and
does not use `(safety 0)`.

## Tests

The test ASDF system loads these components serially in this order:

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
t/edit-semantic-boundaries-test.lisp
```

Run the full check with:

```console
nix flake check
```
