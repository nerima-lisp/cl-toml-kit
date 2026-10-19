;;;; cl-toml-kit.asd

(in-package #:asdf-user)

(asdf:defsystem "cl-toml-kit"
  :description "Common Lisp toolkit for parsing and emitting TOML"
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  :version "0.3.0"
  :homepage "https://github.com/nerima-lisp/cl-toml-kit"
  :bug-tracker "https://github.com/nerima-lisp/cl-toml-kit/issues"
  :source-control (:git "https://github.com/nerima-lisp/cl-toml-kit.git")
  :pathname "src"
  :serial t
  :depends-on (;; Source spans and formatted diagnostics for TOML parse errors.
               (:version "cl-parser-kit" "1.1.1")
               ;; TOML date and time values, parsing, and formatting.
               (:version "cl-date-kit" "1.1.1")
               ;; UTF-8 decoding and encoding.
               (:version "cl-codec-kit" "0.6.0"))
  :components ((:file "package")
               (:file "comment-scan")
               (:file "syntax-data")
               (:file "conditions")
               (:file "data")
               (:file "reader-data")
               (:file "reader-macros")
               (:file "reader-scan")
               (:file "reader-path")
               (:file "reader-values")
               (:file "reader-document")
               (:file "writer-data")
               (:file "writer-macros")
               (:file "writer")
               (:file "reader")
               (:file "edit-model")
               (:file "edit-scan")
               (:file "edit-document")
               (:file "edit-bytes")
               (:file "edit-semantic")
               (:file "edit-splice")
               (:file "edit"))
  :in-order-to ((test-op (test-op "cl-toml-kit/test"))))

(asdf:defsystem "cl-toml-kit/test"
  :description "Test system for cl-toml-kit"
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  :version "0.3.0"
  :depends-on ("cl-toml-kit" "cl-weave" "cl-json-kit")
  :pathname "t"
  :serial t
  :components ((:file "package")
               (:file "helpers-values")
               (:file "helpers-values-test")
               (:file "helpers-edit")
               (:file "helpers-edit-test")
               (:file "conditions-test")
               (:file "data-test")
               (:file "writer-test")
               (:file "fixture-toml-test")
               (:file "reader-values-test")
               (:file "comment-scan-test")
               (:file "reader-document-test")
               (:file "reader-errors-test")
               (:file "roundtrip-test")
               (:file "reader-conformance-test")
               (:file "edit-test")
               (:file "edit-boundaries-test"))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (unless (funcall (symbol-function
                               (find-symbol "RUN-TESTS" "CL-TOML-KIT/TEST")))
               (error "cl-toml-kit test suite failed"))))

(asdf:defsystem "cl-toml-kit/benchmark"
  :description "Diagnostic benchmark definitions for cl-toml-kit"
  :author "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  :version "0.3.0"
  :depends-on ("cl-toml-kit")
  :pathname "benchmark"
  :serial t
  :components ((:file "runner")
               (:file "cases")))
