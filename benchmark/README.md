# Benchmarks

The benchmark system is diagnostic. It is not a merge gate and must not be
used to weaken correctness checks. Cases are declared with
`cl-toml-kit/benchmark:define-benchmark` so the system can load before the
reader and writer implementations are present.

Run it with:

```sh
timeout 600 sbcl --script run-benchmarks.lisp
```

The harness reports wall-clock seconds and SBCL `bytes-consed` for generated
inputs of 256, 512, and 1024 entries. It also reports the ratio for each
size-doubling pair. A pair passes the linear-order check when both ratios are
at most 4.0; each case must also remain below its time and allocation upper
bounds.
Reader cases are reported as `PENDING` until `cl-toml-kit:parse` is available.
Pending cases do not fail the diagnostic run. Other failures return a non-zero
status, which makes the workflow useful without turning the benchmark into a
correctness gate.

## Competitor comparison

The optional clop comparison is isolated from the regular benchmark and does
not add a project dependency. Point `CL_TOML_KIT_CLOP_DIR` at a shallow clone
of clop, then run:

```sh
CL_TOML_KIT_CLOP_DIR=/tmp/clop \
  sbcl --script benchmark/run-competitors.lisp
```

The comparison first requires both parsers to produce the same normalized
result for one input. A missing competitor, unavailable dependency, or load
failure is reported as `skip` with its reason. Successful measurements use
warmup 2 and samples 10, and report median parse time, median
`bytes-consed`, `clop - cl-toml-kit` allocation delta, and allocation ratio
for the same generated inputs.
