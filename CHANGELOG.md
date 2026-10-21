# Changelog

## 0.3.0

### Reader

- The nesting limit now covers arrays, inline tables, dotted keys, table headers, and array-of-tables headers. The same limit applies when editing TOML source.
- The hard input-character ceiling is now 67,108,864 characters.
- The continuation-based reader's parse workloads took roughly 1.1 to 1.6 times as long as with the earlier parser in measurements from the refactor. The measurements used two warmups followed by 10 samples of 10 iterations, with a full garbage collection before each sample. This throughput cost is accepted with the security changes in this release.
