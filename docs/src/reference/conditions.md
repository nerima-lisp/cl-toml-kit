# Conditions

`cl-toml-kit` signals typed conditions with structured, machine-readable
slots. Parse, encoding, and format-preservation error helpers normalize
diagnostic strings before storing them. Report methods normalize messages again
when printing, including values supplied through direct condition construction.
The `toml-value-model-error-message` reader is an exception: it returns the
stored value unchanged, even when that value is not a string; only the report
method normalizes it for printing.
Each diagnostic string is limited to 256 characters after escaping, except
`expected`, which is limited to 128 characters. Integer `line`, `column`, and
`position` values are printed as decimal numbers and are not subject to these
limits.
In diagnostic strings, newlines, carriage returns, tabs, and backspaces use
`\n`, `\r`, `\t`, and `\b`; other C0 and C1 control characters use `\uXXXX`.
Surrogate code points also use `\uXXXX`.
Stored error paths retain at most 32 components and end with `:...` when
truncated. Their printed form is limited to 256 characters, and each component
is limited to 64 printed characters. String path components escape controls
and surrogate code points. Integer components remain integers when their
printed form fits both caps; otherwise, oversized integers use the bounded
`integer` label. Other components become bounded strings or short type labels.

## The shared base condition

`toml-kit-error` is a subtype of `error` and the base of the library-defined
error conditions. It carries no slots. Some operations can also signal ordinary
Common Lisp conditions. For example, `write-toml` signals `type-error` for a
non-stream, and `parse-file` can propagate file conditions.

See also: [`toml-kit-error`](api.md#toml-kit-error).

## TOML value model error

`toml-value-model-error` is a subtype of `toml-kit-error`. The
`toml-value-typecase` macro signals it during macro expansion when a clause
uses an unknown TOML kind keyword. Read `toml-value-model-error-message` for
the explanation. For an unknown kind, the macro stores a string that the
reader returns without escaping or truncation. A long kind name can make that
string exceed the diagnostic limit. Direct `make-condition` calls can also
store a non-string message, which the reader returns unchanged. The report
method sanitizes and bounds the message only when printing the condition.

See also: [`toml-value-model-error`](api.md#toml-value-model-error).

## TOML parse error

Malformed TOML, input-limit errors from `parse` or `parse-file`, and invalid
UTF-8 from `parse-file` signal `toml-parse-error`, a subtype of
`toml-kit-error`. Its public readers are:

| Reader | Meaning |
| --- | --- |
| `toml-parse-error-source-name` | Bounded, sanitized diagnostic text derived from `source-name`; `nil` if omitted or supplied as `nil`. |
| `toml-parse-error-position` | Zero-based character offset where parsing failed; `0` for a `parse-file` byte-limit error; byte offset for a `parse-file` UTF-8 decoding error. Default `0`. |
| `toml-parse-error-line` | One-based line number where parsing failed, or `nil` when a byte or character input-size limit is exceeded before TOML parsing. Default `1`. |
| `toml-parse-error-column` | One-based column number where parsing failed, or `nil` when a byte or character input-size limit is exceeded before TOML parsing. Default `1`. |
| `toml-parse-error-path` | Path of table keys and vector indices from the document root to the failure; `nil` when no path applies. |
| `toml-parse-error-expected` | Short description of what the parser expected; `nil` when the parser did not record one. |
| `toml-parse-error-context` | The context label of the failure; defaults to `"TOML"`. |
| `toml-parse-error-text` | A bounded, sanitized snippet of the input near the failure. Default `""`. |

The library normalizes `source-name` only when it signals `toml-parse-error`.
Pathnames are converted with `namestring`; other values become diagnostic text.
Control characters in that text are escaped, then it is capped at 256 characters.
`nil` remains `nil`. The report prints the normalized text with `~A`.

```lisp
(handler-case
    (cl-toml-kit:parse "name = \"unterminated" :source-name "config.toml")
  (cl-toml-kit:toml-parse-error (condition)
    (list :source-name (cl-toml-kit:toml-parse-error-source-name condition)
          :position     (cl-toml-kit:toml-parse-error-position condition)
          :line         (cl-toml-kit:toml-parse-error-line condition)
          :column       (cl-toml-kit:toml-parse-error-column condition)
          :expected     (cl-toml-kit:toml-parse-error-expected condition))))
```

The `:report` method renders the condition as one human-readable line. The
`in <source-name>` part appears only when a source name was given, `at <path>`
only when a path applies, and `; expected <expected>` only when the parser
recorded an expected value. `context` and `text` are available only through
their readers. For the input above, an illustrative report (not a stable
wording contract) is:

```text
TOML parse error in config.toml at line 1, column 21 (position 20); expected closing string delimiter
```

See also: [`toml-parse-error`](api.md#toml-parse-error).

## TOML encoding error

The writer signals `toml-encoding-error`, a subtype of `toml-kit-error`, for
values that cannot be represented in TOML. Its public readers are:

| Reader | Meaning |
| --- | --- |
| `toml-encoding-error-message` | A bounded description of the failure. Defaults to `"TOML encoding failed"`. |
| `toml-encoding-error-path` | The path from the root table to the offending value; `nil` when the failure is at the top level. String components normally identify table keys, and integer components normally identify vector indices. Rejected table keys may be normalized for display; for example, a symbol becomes its name and an oversized integer may become `"integer"`. A final `:...` marks truncation. |

An integer outside the signed 64-bit range triggers it:

```lisp
(handler-case
    (cl-toml-kit:encode
     (let ((table (make-hash-table :test 'equal)))
       (setf (gethash "n" table) (ash 1 63))
       table))
  (cl-toml-kit:toml-encoding-error (condition)
    (list (cl-toml-kit:toml-encoding-error-message condition)
          (cl-toml-kit:toml-encoding-error-path condition))))
;; => ("Integer is outside TOML's signed 64-bit range (value integer)"
;;     ("n"))
```

`(ash 1 63)` is one past the signed 64-bit maximum. The message identifies the
value's category with a `(value <category>)` label and does not print the
rejected object. A `nil` value produces `Unsupported TOML value (value null)`.

The writer also rejects cyclic values and values deeper than
`*toml-max-nesting-depth*`. The top-level table is not counted; each nested
table or array adds one level. The default is 256; see [shared processing
limits](api.md#shared-processing-limits). Strings or keys that contain
surrogate code points are also rejected. Each failure signals
`toml-encoding-error`.

An illustrative `:report` output (not a stable wording contract) is:

```text
TOML encode error at ("n"): Integer is outside TOML's signed 64-bit range (value integer)
```

The `at <path>` part appears only when a path applies.

See also: [`toml-encoding-error`](api.md#toml-encoding-error).

## `toml-format-preservation-error`

This condition is signaled when an edit cannot identify one safe source span
without rewriting unrelated bytes. `toml-format-preservation-error-message`
returns the explanation and `toml-format-preservation-error-path` returns the
requested logical path.

`edit-toml` rejects malformed input with `toml-parse-error` before applying an
edit. It signals `toml-format-preservation-error` when a path is ambiguous,
including when it matches multiple source values, omits an array-of-tables
index, or requests a structural change inside an ambiguous dotted-key
definition. It also signals this condition when an addition or deletion would
make comment, delimiter, or table ownership unclear; when a deletion would
remove or strand a comment; or when an array insertion would cross a trailing
element comment. Nesting-limit failures while scanning the source or validating
the edited result also signal this condition. After an edit, a parsed-value
mismatch signals this condition. Omitting both `new-value` and `:delete t` from
an `edit-toml` call signals this condition; passing `nil` as `new-value` does
not request deletion. The input byte vector is unchanged when `edit-toml`
signals `toml-parse-error` or `toml-format-preservation-error`.

## Reports

Each concrete condition defines a `:report` method that renders it as a single
human-readable line. The wording is not a stable contract:
programs should read the accessors in the tables above instead of parsing
report text.

## Catching library conditions

Here, `process` and `report-failure` are caller-supplied placeholders:

```lisp
(handler-case
    (process (cl-toml-kit:parse-file #p"config.toml"))
  (cl-toml-kit:toml-kit-error (condition)
    (report-failure condition)))
```

See [API Reference](api.md#toml-parse-error) for the individual symbols and
[Troubleshooting](../guide/troubleshooting.md) for symptom-driven help.
