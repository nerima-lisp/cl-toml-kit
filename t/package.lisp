;;;; t/package.lisp
(defpackage #:cl-toml-kit/test
  (:use #:cl #:cl-toml-kit)
  (:shadowing-import-from #:cl-weave #:describe)
  (:import-from #:cl-weave #:it #:expect #:signals #:run-all)
  (:export #:run-tests))

(in-package #:cl-toml-kit/test)

(defun run-tests ()
  "Run the foundation model and condition specifications."
  (unless (run-all :reporter :spec :timeout-ms 10000)
    (error "cl-toml-kit test suite failed"))
  t)
