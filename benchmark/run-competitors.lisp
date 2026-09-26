;;;; Run the optional competitor benchmark from the repository root.
(require :asdf)
(asdf:load-asd (merge-pathnames "cl-toml-kit.asd"
                                (uiop:pathname-parent-directory-pathname
                                 (uiop:pathname-directory-pathname
                                  (or *load-truename* *default-pathname-defaults*)))))
(load (merge-pathnames "competitors.lisp"
                       (uiop:pathname-directory-pathname
                        (or *load-truename* *default-pathname-defaults*))))
(when (eq :failed
          (cl-toml-kit/benchmark-competitors:run-competitor-benchmarks))
  (error "Competitor correctness or measurement gate failed"))
