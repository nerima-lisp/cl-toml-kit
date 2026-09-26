# Conditions

Parse failures signal `toml-parse-error` with source name, line, column, and
offset. Encoding failures signal `toml-encoding-error` with the offending
value and path. See the [architecture contract](../project/architecture.md).
