# Architecture

This is the implementation contract for the parallel Reader and Writer
streams. It is normative for names, ownership, and observable behaviour.

## Ownership and layout

The foundation owns `src/package.lisp`, `src/conditions.lisp`, `src/data.lisp`,
`src/model-macros.lisp`, and model/condition tests. Reader owns only
`src/reader*.lisp` and `t/reader*-test.lisp`; Writer owns only
`src/writer*.lisp` and `t/writer*-test.lisp`. `t/fixtures/` is owned by the
conformance stream and must not be edited by any of these streams.

ASDF loads package, data tables, conditions, model macros, model, then reader
and writer files. Reader and Writer may use model and conditions, never each
other's private helpers.

## Public API

```lisp
(parse source &key source-name)
(encode value &key pretty)
```

`source` is a string or character input stream. `source-name` labels
diagnostics. `parse` returns one ordered TOML table and signals
`toml-parse-error` for invalid input. `encode` returns a string and signals
`toml-encoding-error` for unrepresentable values. `pretty` controls spacing;
the default is deterministic compact output. These are functions, not macros.

The model API is `make-string-value`, `make-integer-value`,
`make-float-value`, `make-boolean-value`, `make-array-value`,
`make-table-value`, `value-type`, `value-p`, `array-elements`,
`table-entries`, and `table-value`. Date values are the cl-date-kit objects
directly, without adapters.

## Data model

| TOML value | Lisp representation | Notes |
| --- | --- | --- |
| string | string value object | Separate from table keys. |
| integer | integer value object | Never coerced to float. |
| float | float value object | Includes infinity and NaN. |
| boolean | boolean value object | False is distinct from `nil` and absence. |
| offset date-time | `cl-date-kit:offset-date-time` | Used directly. |
| local date-time | `cl-date-kit:local-date-time` | Used directly. |
| local date | `cl-date-kit:local-date` | Used directly. |
| local time | `cl-date-kit:local-time` | Used directly. |
| array | ordered array value object | Empty arrays remain present. |
| table | ordered table value object | Key order is retained. |
| inline table | table value with inline marker | Controls writer layout. |
| array of tables | table-entry metadata | Distinct from an ordinary array. |

The declarative value-type table in `src/data.lisp` is the source of truth;
`src/model-macros.lisp` generates predicates and constructors from it. This
is an internal definition DSL, not the public data API.

## Conditions

`toml-kit-error` is the root. `toml-parse-error` adds `source-name`, `line`,
`column`, and `offset`. `toml-encoding-error` identifies the offending value
and path. Concrete conditions include `toml-invalid-syntax`,
`toml-invalid-value`, and `toml-unsupported-value`. Every condition has a
`:report` method and readers for public diagnostic slots.

## CPS and macros

Parser token and grammar helpers may use CPS for success, failure, and source
location propagation. CPS stays inside Reader; `parse` presents ordinary
values and conditions. Writer may use a continuation for streaming output,
but `encode` returns a string. Tables, labels, and diagnostic text are data;
traversal and validation are logic.

Macros are used only for generated definitions and repetitive syntax. Public
parse/encode operations remain functions, as required by the API standard.

## Tests and fixtures

Foundation tests cover every model constructor, predicate, accessor, empty
collection, ordered-table operation, direct date-kit value, and condition
report/accessor. `cl-weave` is the test framework. Conformance fixtures are
read from `t/fixtures/` and never copied or modified. Reader tests assert
parsed values; Writer tests assert deterministic output and round trips.
Property tests cover parse/encode round trips after both streams land. Flake
checks include tests, coverage, formatting, and paredit lint.
