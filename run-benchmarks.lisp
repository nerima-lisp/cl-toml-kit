;;;; Diagnostic benchmark entry point.
(require :asdf)
(asdf:load-asd (merge-pathnames "cl-toml-kit.asd"
                                (uiop:pathname-directory-pathname
                                 (or *load-truename* *default-pathname-defaults*))))
(asdf:load-system "cl-toml-kit/benchmark")
(cl-toml-kit/benchmark:run-benchmarks)
