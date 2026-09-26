# Benchmarks

The benchmark system is diagnostic. It is not a merge gate and must not be
used to weaken correctness checks. Cases are declared with
`cl-toml-kit/benchmark:define-benchmark` so the system can load before the
reader and writer implementations are present.

Run it with:

```sh
timeout 600 sbcl --script run-benchmarks.lisp
```

The harness reports wall-clock seconds and is intended for controlled local or
CI comparisons on the same machine and Nix lockfile.
