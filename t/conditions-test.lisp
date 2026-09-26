;;;; t/conditions-test.lisp
(in-package #:cl-toml-kit/test)

(describe "TOML conditions"
  (it "reports every parse diagnostic accessor"
    (let ((condition (make-condition 'toml-parse-error
                                     :source-name "input.toml"
                                     :position 4 :line 2 :column 3
                                     :path '("root" 1) :expected "value"
                                     :context "table" :text "x =")))
      (expect (string= "input.toml" (toml-parse-error-source-name condition)))
      (expect (= 4 (toml-parse-error-position condition)))
      (expect (= 2 (toml-parse-error-line condition)))
      (expect (= 3 (toml-parse-error-column condition)))
      (expect (equal '("root" 1) (toml-parse-error-path condition)))
      (expect (string= "value" (toml-parse-error-expected condition)))
      (expect (string= "table" (toml-parse-error-context condition)))
      (expect (string= "x =" (toml-parse-error-text condition)))
      (expect (plusp (length (with-output-to-string (stream)
                              (write condition :stream stream)))))))
  (it "reports encoding message and path"
    (let ((condition (make-condition 'toml-encoding-error
                                     :message "bad value" :path '("x"))))
      (expect (string= "bad value" (toml-encoding-error-message condition)))
      (expect (equal '("x") (toml-encoding-error-path condition)))
      (expect (plusp (length (with-output-to-string (stream)
                              (write condition :stream stream))))))))
