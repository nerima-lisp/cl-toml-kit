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
