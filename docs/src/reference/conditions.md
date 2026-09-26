# Conditions

All library conditions inherit from `toml-kit-error`.

`toml-parse-error` reports malformed TOML and provides these readers:

`toml-parse-error-source-name`, `toml-parse-error-position`,
`toml-parse-error-line`, `toml-parse-error-column`, `toml-parse-error-path`,
`toml-parse-error-expected`, `toml-parse-error-context`, and
`toml-parse-error-text`.

`toml-encoding-error` reports values that cannot be represented in TOML and
provides `toml-encoding-error-message` and `toml-encoding-error-path`.

Both concrete conditions define a `:report` method. Programs should use the
accessors for diagnostics rather than parsing report text. See the
[architecture contract](../../design/architecture.md) for the condition
hierarchy and value rules.
