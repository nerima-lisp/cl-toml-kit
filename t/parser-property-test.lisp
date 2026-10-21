(in-package #:cl-toml-kit/test)

(describe "TOML parser generated values"
  (it-property "parses generated TOML documents against independent values"
      ((document (toml-test-source-document-generator)))
    (destructuring-bind (source expected) document
      (expect (toml-test-value= expected (parse source))))))
