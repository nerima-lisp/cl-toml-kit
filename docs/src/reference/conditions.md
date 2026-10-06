# Conditions

`cl-toml-kit` signals typed conditions with structured, machine-readable
slots. Diagnostic strings are bounded and sanitized when the condition is
constructed, so logging a condition cannot echo unbounded input. The error
path is limited to 32 components; each component that is neither a string nor
an integer is printed with a 64-character bound. `expected` is truncated to
128 characters, and `context` and `text` are truncated to 256 characters.
Newlines, carriage returns, tabs, and backspaces are escaped as `\n`, `\r`,
`\t`, and `\b`.

## The shared base condition

`toml-kit-error` is a subtype of `error` and the base of every condition this
library signals. It carries no slots. Catch it when you want to react to any
failure from `cl-toml-kit` without distinguishing parse from encoding
failures; the concrete types below add the readers you can use once you
catch one.

See also: [`toml-kit-error`](api.md#toml-kit-error).

## TOML parse error

Malformed TOML input signals `toml-parse-error`, a subtype of
`toml-kit-error`. Its public readers are:

| Reader | Meaning |
| --- | --- |
| `toml-parse-error-source-name` | The `source-name` designator supplied to `parse`; `nil` if none was given. |
| `toml-parse-error-position` | Zero-based character offset in the input where parsing failed. Default `0`. |
| `toml-parse-error-line` | One-based line number where parsing failed. Default `1`. |
| `toml-parse-error-column` | One-based column number where parsing failed. Default `1`. |
| `toml-parse-error-path` | Path of table keys and vector indices from the document root to the failure; `nil` when no path applies. |
| `toml-parse-error-expected` | Short description of what the parser expected; `nil` when the parser did not record one. |
| `toml-parse-error-context` | The context label of the failure; defaults to `"TOML"`. |
| `toml-parse-error-text` | A bounded, sanitized snippet of the input near the failure. Default `""`. |

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

The condition's `:report` method combines these into a single human-readable
line of this shape:

```text
TOML parse error in <source-name> at line <line>, column <column> (position <position>) at <path>; expected <expected>
```

The `in <source-name>` part appears only when a source name was given, `at
<path>` only when a path applies, and `; expected <expected>` only when the
parser recorded an expected value. `context` and `text` are available only
through their readers. The following is an example report from the implemented
reader:

```text
TOML parse error in config.toml at line 3, column 9 (position 41) at ("server" "port"); expected value
```

See also: [`toml-parse-error`](api.md#toml-parse-error).

## TOML encoding error

The writer signals `toml-encoding-error`, a subtype of `toml-kit-error`, for
values that cannot be represented in TOML. Its public readers are:

| Reader | Meaning |
| --- | --- |
| `toml-encoding-error-message` | A bounded description of the failure. Defaults to `"TOML encoding failed"`. |
| `toml-encoding-error-path` | The path from the root table to the offending value; `nil` when the failure is at the top level. String components are table keys and nonnegative integers are vector indices. |

Encoding an integer outside the signed 64-bit range triggers it:

```lisp
(handler-case
    (cl-toml-kit:encode
     (let ((table (make-hash-table :test 'equal)))
       (setf (gethash "n" table) (ash 1 63))
       table))
  (cl-toml-kit:toml-encoding-error (condition)
    (list (cl-toml-kit:toml-encoding-error-message condition)
          (cl-toml-kit:toml-encoding-error-path condition))))
;; => ("Integer is outside TOML's signed 64-bit range (value 9223372036854775808)"
;;     ("n"))
```

`(ash 1 63)` is `9223372036854775808`, one past the signed 64-bit maximum.
The message appends `(value ~S)`, printed with `*print-length*` bound to 10
and `*print-level*` bound to 3. A `nil` value is another common trigger and
produces the message `Unsupported TOML value (value NIL)`.

The `:report` method renders the condition as one line:

```text
TOML encode error at ("n"): Integer is outside TOML's signed 64-bit range (value 9223372036854775808)
```

The `at <path>` part appears only when a path applies.

See also: [`toml-encoding-error`](api.md#toml-encoding-error).

## `toml-format-preservation-error`

This condition is signaled when an edit cannot identify one safe source span
without rewriting unrelated bytes. `toml-format-preservation-error-message`
returns the explanation and `toml-format-preservation-error-path` returns the
requested logical path.

Malformed input is rejected by `toml-parse-error` before an edit is applied.
This condition covers paths that match more than one source value, unindexed
array-of-tables paths, structural edits inside ambiguous dotted-key
definitions, and additions or deletions whose comments, delimiters, or table
ownership cannot be determined. The input byte vector is not modified when
either condition is signaled.

## Reports

Both concrete conditions define a `:report` method that renders the condition
as a single human-readable line. The wording is not a stable contract:
programs should read the accessors in the tables above instead of parsing
report text.

## Catching all failures

Both conditions are subtypes of `error`, so the ordinary `handler-case` and
`handler-bind` machinery applies. To react to any failure from `cl-toml-kit`
without distinguishing parse from encoding failures, catch `toml-kit-error`:

```lisp
(handler-case
    (process (cl-toml-kit:parse-file #p"config.toml"))
  (cl-toml-kit:toml-kit-error (condition)
    (report-failure condition)))
```

See [API Reference](api.md#toml-parse-error) for the individual symbols and
[Troubleshooting](../guide/troubleshooting.md) for symptom-driven help.
