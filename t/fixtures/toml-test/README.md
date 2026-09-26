# toml-test fixtures

Vendored conformance-test data from
[toml-lang/toml-test](https://github.com/toml-lang/toml-test), used to check the
TOML reader and writer in this repository against the official suite.

This directory holds data only. The code that runs these fixtures lives
elsewhere in the repository, under `t/`.

## Provenance

| Field | Value |
|---|---|
| Upstream repository | <https://github.com/toml-lang/toml-test> |
| Tag | `v2.2.0` |
| Commit | `ce08da1ddb075d1c7596d663c7fcba9a2ae02c5c` |
| TOML specification version | `1.1.0` |
| Upstream manifest | `tests/files-toml-1.1.0` |

## Contents

The layout mirrors the upstream `tests/` tree:

```
t/fixtures/toml-test/
  valid/              214 .toml files, each with a matching .json expectation
  invalid/            467 .toml files that a decoder must reject
  files-toml-1.1.0    upstream manifest: the exact 895 imported paths
  LICENSE             upstream MIT license, verbatim
  README.md           this file
```

895 fixture files in total: 214 valid `.toml`/`.json` pairs (428 files) plus 467
invalid `.toml` files.

## Selection

The upstream `tests/` tree cannot be copied wholesale because it mixes tests for
TOML 1.0.0 and TOML 1.1.0. The authoritative selection for 1.1.0 is the upstream
manifest `tests/files-toml-1.1.0`, which upstream generates with:

```
toml-test list -toml=1.1.0
```

This import copies exactly the paths listed in that manifest, preserving their
relative paths under `valid/` and `invalid/`. Because the manifest is a plain
list of files, it is kept in this directory so the consumed set is reproducible.

Files present upstream but excluded here:

- `valid/spec-1.0.0/`: 48 `.toml` plus 48 `.json`
- `invalid/spec-1.0.0/`: 8 `.toml`
- nine non-spec invalid tests that hold only for TOML 1.0.0:
  - `invalid/datetime/no-secs.toml`
  - `invalid/inline-table/linebreak-01.toml`
  - `invalid/inline-table/linebreak-02.toml`
  - `invalid/inline-table/linebreak-03.toml`
  - `invalid/inline-table/linebreak-04.toml`
  - `invalid/inline-table/trailing-comma.toml`
  - `invalid/local-datetime/no-secs.toml`
  - `invalid/local-time/no-secs.toml`
  - `invalid/string/basic-byte-escapes.toml`

Upstream `.multi` files are generator sources rather than fixtures, so they are
not imported.

## Encoder support

Upstream encoders and decoders share the valid fixtures; there is no separate
encoder directory. A decoder test reads `valid/<name>.toml` and compares the
parsed result against `valid/<name>.json`. An encoder test reads
`valid/<name>.json` and compares the produced TOML against `valid/<name>.toml`.
TOML allows several spellings for the same value (`255` and `0xff`, `0.0` and
`-0.0`), so encoder comparison is semantic rather than textual.

## Expected JSON format

The expectation files use the tagged JSON described by upstream.

- A TOML table is a JSON object.
- A TOML array is a JSON array.
- Every TOML value is a JSON object of the form
  `{"type": "<TOML_TYPE>", "value": "<string>"}`.
- `TOML_TYPE` is one of `string`, `integer`, `float`, `bool`, `datetime`,
  `datetime-local`, `date-local`, `time-local`.
- `value` is always a JSON string.
- An empty table is `{}` and an empty array is `[]`.

Datetime values follow RFC 3339: offset datetimes include the offset, local
datetimes omit it, local dates carry only the date part, and local times carry
only the time part.

Examples:

```toml
a = 42
```

```json
{"type": "integer", "value": "42"}
```

```toml
[tbl]
a = 42
```

```json
{"tbl": {"a": {"type": "integer", "value": "42"}}}
```

```toml
a = ["a", 2]
```

```json
{"a": [{"type": "string", "value": "a"}, {"type": "integer", "value": "2"}]}
```

## License

The fixtures and `LICENSE` come from toml-lang/toml-test and are under the MIT
license, `Copyright (c) 2018 TOML authors`. See [LICENSE](./LICENSE).

## Updating

Run the update script from the repository root:

```
TOML_VERSION=1.1.0 scripts/update-toml-test-fixtures.sh [TAG]
```

With no `TAG`, the script selects the highest `vX.Y.Z` release tag. Otherwise it
uses the tag you pass. It clones the tag into a temporary directory, re-copies
the paths listed in `tests/files-toml-$TOML_VERSION`, refreshes `LICENSE`, and
prints a summary. The script never stages or commits changes.

The equivalent manual sequence, using a shell with `mktemp` and `cp -p`:

```
TAG=v2.2.0
TOML_VERSION=1.1.0
SRC=$(mktemp -d)
git clone --depth 1 --branch "$TAG" https://github.com/toml-lang/toml-test "$SRC"
DEST=t/fixtures/toml-test
while IFS= read -r rel; do
  mkdir -p "$DEST/$(dirname "$rel")"
  cp -p "$SRC/tests/$rel" "$DEST/$rel"
done < "$SRC/tests/files-toml-$TOML_VERSION"
cp -p "$SRC/tests/files-toml-$TOML_VERSION" "$DEST/"
cp -p "$SRC/LICENSE" "$DEST/"
```

After updating, refresh the tag and commit in the Provenance table above and
commit the changed fixture files.
