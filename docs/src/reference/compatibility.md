# Compatibility

## TOML version

`cl-toml-kit` is a reader and a writer for [TOML v1.1.0](https://toml.io/en/v1.1.0).
`parse` and `parse-file` read TOML v1.1.0 documents into the native values
described in [Data model](../guide/data-model.md), and `encode` and `write-toml`
write those values back to TOML v1.1.0.

## Conformance

Conformance is checked against fixtures vendored from
[toml-lang/toml-test](https://github.com/toml-lang/toml-test), the official
test suite for TOML parsers and emitters. The vendored corpus lives under
`t/fixtures/toml-test/`.

| Field | Value |
|---|---|
| Tag | `v2.2.0` |
| Commit | `ce08da1ddb075d1c7596d663c7fcba9a2ae02c5c` |
| Selection manifest | `tests/files-toml-1.1.0` |

The selection follows the upstream manifest `tests/files-toml-1.1.0`, which
upstream generates with `toml-test list -toml=1.1.0`. It contains 214 valid
`.toml`/`.json` pairs and 467 invalid `.toml` files, 895 files in all.

All checks run against the vendored files; nothing is fetched at build or test
time. The reader tests accept all 214 valid fixtures and reject all 467 invalid
fixtures. A separate round-trip test parses each valid fixture, encodes the
result, reparses it, and compares the values.

To refresh the corpus from a chosen upstream tag, run
`TOML_VERSION=1.1.0 scripts/update-toml-test-fixtures.sh [TAG]` from the
repository root.

## Supported implementation

SBCL is the only supported implementation. The writer relies on SBCL's
insertion-order hash-table traversal to preserve key order within each group.
It writes values first, followed by tables and then arrays of tables. Other
Common Lisp implementations are not supported and not verified. The Nix flake
provides outputs for `x86_64-linux` only. CI runs the full flake checks there.
macOS developers can run the Lisp test suite with SBCL by following the ASDF
setup in [Getting Started](../getting-started.md).

## Dependencies

| System | Minimum version | Role |
|---|---|---|
| `cl-parser-kit` | 1.1.1 | runtime |
| `cl-date-kit` | 1.2.0 | runtime |
| `cl-codec-kit` | 0.6.0 | runtime |
| `cl-weave` | 1.4.0 | test only |
| `cl-json-kit` | 1.2.0 | test only |

The library requires the minimum runtime dependency versions declared in
`cl-toml-kit.asd`. The flake locks build inputs and pins tooling
(`cl-nix-forge`, `paredit-cli`, `treefmt-nix`); these tools are not library
dependencies. `cl-date-kit` provides the date and time types in the
[value mapping](../guide/data-model.md). Adding the library to your project is
covered in [Getting started](../getting-started.md).

## Stability

Version 0.3.0 is pre-1.0 (see `:version` in `cl-toml-kit.asd`). Exported
symbols and their behavior may change without a deprecation window; documented
behavior is the only compatibility promise.

Once 1.0.0 is released, the exported surface is intended to follow
[Semantic Versioning](https://semver.org/). That surface is the `cl-toml-kit`
package symbols documented in [API reference](api.md) and
[Conditions](conditions.md), and the value mapping documented in
[Data model](../guide/data-model.md). A breaking change to it then requires a
major version bump. No deprecation policy exists yet. Breaking changes are
listed in the changelog for each release.
