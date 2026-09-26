# Reader

`cl-toml-kit:parse` accepts a string or character input stream and returns a
top-level TOML table. Invalid input signals `toml-parse-error` with source
position and a cl-parser-kit diagnostic excerpt.

The reader uses cl-parser-kit for source spans and diagnostics, but not for
tokenization. TOML lexemes depend on context: `true` and `1979-05-27` are valid
keys as well as value spellings. The reader therefore performs
context-sensitive scanning directly and hands only spans and diagnostics to
cl-parser-kit.
