;;;; cl-toml-kit.asd

(in-package #:asdf-user)

(asdf:defsystem "cl-toml-kit"
  :description "Common Lisp toolkit for parsing and emitting TOML"
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  :version "0.1.0"
  :homepage "https://github.com/nerima-lisp/cl-toml-kit"
  :bug-tracker "https://github.com/nerima-lisp/cl-toml-kit/issues"
  :source-control (:git "https://github.com/nerima-lisp/cl-toml-kit.git")
  :pathname "src"
  :serial t
  :depends-on ((:version "cl-parser-kit" "1.1.1")
               (:version "cl-date-kit" "1.0.0"))
  :components ((:file "package")
               (:file "conditions")
               (:file "data")
               (:file "model")
               (:file "writer-data")
               (:file "writer"))
  :in-order-to ((test-op (test-op "cl-toml-kit/test"))))

(asdf:defsystem "cl-toml-kit/test"
  :description "Test system for cl-toml-kit"
  :author "takeokunn <bararararatty@gmail.com>"
  :maintainer "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  :version "0.1.0"
  :depends-on ("cl-toml-kit" "cl-weave")
  :pathname "t"
  :serial t
  :components ((:file "package")
               (:file "conditions-test")
               (:file "model-test")
               (:file "writer-test"))
  :perform (test-op (operation component)
             (declare (ignore operation component))
             (unless (funcall (symbol-function
                               (find-symbol "RUN-TESTS" "CL-TOML-KIT/TEST")))
               (error "cl-toml-kit test suite failed"))))

(asdf:defsystem "cl-toml-kit/benchmark"
  :description "Diagnostic benchmark definitions for cl-toml-kit"
  :author "takeokunn <bararararatty@gmail.com>"
  :license "MIT"
  :version "0.1.0"
  :depends-on ("cl-toml-kit")
  :pathname "benchmark"
  :serial t
  :components ((:file "runner")))
