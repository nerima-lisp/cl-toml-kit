# Reader

The reader accepts TOML 1.1.0 text and returns a top-level hash table. It is
implemented for SBCL and supports strings, character streams, and UTF-8 files.

## Parsing text and files

```lisp
(cl-toml-kit:parse source &key source-name)
(cl-toml-kit:parse-file pathname)
```

`parse` accepts a string or a character input stream. `source-name` is optional
and is included in parse diagnostics.

```lisp
(cl-toml-kit:parse (format nil "title = \"Example\"~%count = 2~%"))

(with-open-file (stream "config.toml")
  (cl-toml-kit:parse stream :source-name "config.toml"))

(cl-toml-kit:parse-file #P"config.toml")
```

`parse-file` reads bytes as UTF-8, including characters outside the BMP. An
invalid UTF-8 sequence signals `toml-parse-error`; it has no encoding option.

## Values

| TOML value | Common Lisp value |
| --- | --- |
| table or inline table | `hash-table` with the `equal` test |
| array or array of tables | `simple-vector` |
| string | `string` |
| integer | signed 64-bit `integer` |
| float | `double-float` |
| `true` | `t` |
| `false` | `cl-toml-kit:+toml-false+` |
| offset date-time | `cl-date-kit:offset-date-time` |
| local date-time | `cl-date-kit:local-date-time` |
| local date | `cl-date-kit:local-date` |
| local time | `cl-date-kit:local-time` |

Decimal integers do not allow leading zeroes, and underscores are allowed only
between digits. The reader supports `0x`, `0o`, and `0b` integers, decimal
floats, `inf`, `-inf`, and `nan`. Date and time values are parsed with
cl-date-kit's `:profile :rfc3339`.

Basic strings support `\\b`, `\\t`, `\\n`, `\\f`, `\\r`, `\\e`, `\\"`,
`\\\\`, `\\xHH`, `\\uHHHH`, and `\\UHHHHHHHH`. Literal and multiline strings,
CRLF, comments, dotted keys, tables, array tables, and inline tables are
supported.

## Errors

Invalid input signals `toml-parse-error`, which is a subtype of
`toml-kit-error`. Its accessors are:

`toml-parse-error-source-name`, `toml-parse-error-position`,
`toml-parse-error-line`, `toml-parse-error-column`, `toml-parse-error-path`,
`toml-parse-error-expected`, `toml-parse-error-context`, and
`toml-parse-error-text`.

```lisp
(handler-case
    (cl-toml-kit:parse "name = @" :source-name "example.toml")
  (cl-toml-kit:toml-parse-error (condition)
    (format t "~A~%" condition)
    (format t "line=~D column=~D~%"
            (cl-toml-kit:toml-parse-error-line condition)
            (cl-toml-kit:toml-parse-error-column condition))))
```

The printed report includes the source name, line, column, character
position, path when available, and expected input. `text` contains the
cl-parser-kit diagnostic excerpt.

## TOML 1.1.0 coverage

The bundled toml-test v2.2.0 fixtures pass completely: 214 valid fixtures and
467 invalid fixtures. The reader tests also cover stream input, UTF-8 file
input, diagnostics, and parse/encode/parse round trips.

## Design

cl-parser-kit is used for source spans and diagnostics, not as a tokenizer.
TOML lexemes change meaning by context: a token can be a key in one position
and a value in another, so the reader performs context-sensitive scanning
itself. Date and time values are delegated to cl-date-kit with the RFC3339
profile.
