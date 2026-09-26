# Benchmarks

This page records diagnostic measurements for the Writer. Wall-clock values
are for local A/B comparison only. Automated checks use allocation limits and
the observed size-doubling order; they do not gate merges on elapsed time.

## Reproduction

The measurements below were taken on 2026-09-27 with SBCL 2.6.0 on Apple M4
Max, macOS 26.6.2. The source tree was the `takeokunn-toml-perf` worktree at
the benchmark change. Each case uses two warm-up rounds and ten measured
samples. Each sample runs a full GC before the measurement and records
`sb-ext:get-bytes-consed`.

```sh
REPOS=${NERIMA_LISP_REPOS:?Set this to the directory containing the dependency clones}
DEPS=$(mktemp -d)
git -C "$REPOS/cl-parser-kit.git" archive --prefix=cl-parser-kit/ v1.1.1 \
  | tar -x -C "$DEPS"
git -C "$REPOS/cl-date-kit.git" archive --prefix=cl-date-kit/ v1.1.0 \
  | tar -x -C "$DEPS"
git -C "$REPOS/cl-weave.git" archive --prefix=cl-weave/ v1.3.0 \
  | tar -x -C "$DEPS"
sbcl --dynamic-space-size 4096 --non-interactive \
  --eval '(require :asdf)' \
  --eval "(asdf:initialize-source-registry '(:source-registry (:tree \"$DEPS/\") (:directory \"$PWD/\") :ignore-inherited-configuration))" \
  --load run-benchmarks.lisp
```

## Writer results

The generated table contains 256, 512, and 1,024 scalar entries. The values
are representative of this host and corpus, not a universal speed claim.

| Case | Size | Median seconds | Min / max seconds | Median bytes | Time | Bytes | Order |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `encode` | 256 | 0.000097 | 0.000070 / 0.000474 | 132,864 | - | - | - |
| `encode` | 512 | 0.000186 | 0.000126 / 0.000267 | 213,696 | 1.933 | 1.608 | pass |
| `encode` | 1,024 | 0.000365 | 0.000245 / 0.001441 | 297,216 | 1.960 | 1.391 | pass |
| `write-toml` | 256 | 0.000082 | 0.000054 / 0.000104 | 109,568 | - | - | - |
| `write-toml` | 512 | 0.000149 | 0.000096 / 0.000573 | 108,800 | 1.828 | 0.993 | pass |
| `write-toml` | 1,024 | 0.000358 | 0.000215 / 0.018279 | 108,032 | 2.406 | 0.993 | pass |

The Reader cases are registered with the same generated inputs and report
`pending` until `cl-toml-kit:parse` is available.

## Writer change A/B record

The measured hotspot was `write-table`: the previous implementation classified
each hash-table entry once per each of three `maphash` passes. The change in
`src/writer.lisp` classifies entries during one pass and stores only nested
tables for the later sections. It preserves the existing value-before-table
ordering and output bytes.

| Workload | Before ticks | After ticks | Before bytes | After bytes |
| --- | ---: | ---: | ---: | ---: |
| 100 scalar entries | 1,553,808 | 1,485,516 | 150,334,080 | 149,996,032 |
| Nested table | 15,165 | 12,991 | 11,075,584 | 11,993,088 |

The nested workload allocates more because it creates temporary lists for the
deferred table sections. The allocation limit therefore remains the primary
regression guard, while the A/B record explains the trade-off.

No competing TOML implementation was available in the local dependency set,
so no cross-library comparison is recorded.
