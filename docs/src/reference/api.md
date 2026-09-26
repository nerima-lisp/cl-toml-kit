# API reference

The public API consists of four ordinary functions:

```lisp
(cl-toml-kit:parse source &key source-name)
(cl-toml-kit:parse-file pathname)
(cl-toml-kit:encode value)
(cl-toml-kit:write-toml value stream)
```

Native values, `+toml-false+`, and the condition accessors are documented in
the [data model](../guide/data-model.md) and [conditions](conditions.md).
