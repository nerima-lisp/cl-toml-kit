# Benchmarks

This page records diagnostic measurements for the Reader and Writer. Wall-clock
values are for local A/B comparison only. Automated checks use allocation
limits and the observed size-doubling order; they do not gate merges on time.

## Reproduction

The measurements below were taken on 2026-09-27 with SBCL 2.6.0 on Apple M4
Max, macOS 26.6.2. Each case uses two warm-up rounds and ten measured samples.
Each sample runs ten iterations. A full GC is performed before each sample and
the reported allocation is divided by ten.

```sh
REPOS=${NERIMA_LISP_REPOS:?Set this to the directory containing the dependency clones}
DEPS=$(mktemp -d)
git -C "$REPOS/cl-parser-kit.git" archive --prefix=cl-parser-kit/ v1.1.1 \
  | tar -x -C "$DEPS"
git -C "$REPOS/cl-date-kit.git" archive --prefix=cl-date-kit/ v1.1.1 \
  | tar -x -C "$DEPS"
git -C "$REPOS/cl-weave.git" archive --prefix=cl-weave/ v1.3.0 \
  | tar -x -C "$DEPS"
git -C "$REPOS/cl-json-kit.git" archive --prefix=cl-json-kit/ v1.2.0 \
  | tar -x -C "$DEPS"
sbcl --dynamic-space-size 4096 --non-interactive \
  --eval '(require :asdf)' \
  --eval "(asdf:initialize-source-registry '(:source-registry \
    (:tree \"$DEPS/\") (:directory \"$PWD/\") \
    :ignore-inherited-configuration))" \
  --load run-benchmarks.lisp
```

## Phase 2 results

The generated Reader input contains 4,096, 8,192, or 16,384 assignments. The
Writer input contains the same number of alternating integer and string values.
All nine cases passed their allocation and order checks.

| Case | Size | Median seconds | Min / max seconds | Median bytes | Time | Bytes | Order |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `reader/parse` | 4,096 | 0.003749 | 0.003315 / 0.006385 | 1,165,414 | - | - | - |
| `reader/parse` | 8,192 | 0.012678 | 0.006885 / 0.023060 | 2,165,658 | 3.382 | 1.858 | pass |
| `reader/parse` | 16,384 | 0.023307 | 0.017175 / 0.039485 | 4,032,083 | 1.838 | 1.862 | pass |
| `writer/encode` | 4,096 | 0.000933 | 0.000927 / 0.004057 | 878,867 | - | - | - |
| `writer/encode` | 8,192 | 0.002274 | 0.001909 / 0.008327 | 1,674,003 | 2.437 | 1.905 | pass |
| `writer/encode` | 16,384 | 0.007078 | 0.003841 / 0.011116 | 3,307,325 | 3.112 | 1.976 | pass |
| `writer/write-toml` | 4,096 | 0.001105 | 0.000721 / 0.002738 | 5,862 | - | - | - |
| `writer/write-toml` | 8,192 | 0.001741 | 0.001445 / 0.003365 | 5,824 | 1.576 | 0.993 | pass |
| `writer/write-toml` | 16,384 | 0.004969 | 0.002952 / 0.010353 | 5,798 | 2.854 | 0.996 | pass |

The preceding phase measured `write-toml` at about 108KB per call because the
measurement was too coarse. The repeated-difference measurement above isolates
the call and shows the allocation at about 5.8KB for these inputs.

## Profiling summary

`sb-sprof` was run in both `:cpu` and `:alloc` modes on the 16,384-entry
Reader input and the 4,096-entry Writer input. Reader CPU samples were led by
`%source-char`, `%read-key-path`, and `PUTHASH/EQUAL`; allocation samples were
led by `PUTHASH/EQUAL` and `%read-key-path`. Writer CPU samples were led by
`STRING-SOUT`/`%write-string`, while allocation samples were led by
`%write-string` and `%write-string-value`.

The Reader source was not changed in phase 2 because the measured hot paths
are result hash-table insertion and key-path construction, both required by
the current result model. The Writer changes batch contiguous string output
and keep the active path in one adjustable vector, avoiding temporary path
lists and their reversal.

## Competitor comparison

The optional `clop` comparison is implemented in
`benchmark/competitors.lisp` and is skipped when its dependencies are absent.
The shallow clone was available, but ASDF could not load it because the
`alexandria` system was not installed. Therefore no correctness-gated timing
comparison was recorded. When dependencies are available, run:

```sh
CL_TOML_KIT_CLOP_DIR=/tmp/clop sbcl --script benchmark/run-competitors.lisp
```

The comparison uses the same generated inputs, a normalized-output correctness
gate, two warm-up rounds, ten samples, and per-call allocation differences.
