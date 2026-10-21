(in-package #:cl-toml-kit/test)

(describe "TOML parser generated values"
  (it-property "parses mixed syntax with generated integers"
      ((document (toml-test-parser-document-generator)))
    (destructuring-bind (source expected) document
      (expect (toml-test-value= expected (parse source))))))
