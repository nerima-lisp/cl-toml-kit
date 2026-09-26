;;;; t/conditions-test.lisp
(in-package #:cl-toml-kit/test)

(describe "TOML conditions"
  (it "reports parse location and source name"
    (let ((condition (make-condition 'toml-parse-error
                                     :source-name "input.toml"
                                     :position 4 :line 2 :column 3)))
      (expect (string= "input.toml" (toml-parse-error-source-name condition)))
      (expect (= 2 (toml-parse-error-line condition)))
      (expect (= 3 (toml-parse-error-column condition)))))
  (it "reports encoding paths"
    (let ((condition (make-condition 'toml-encoding-error
                                     :message "bad value" :path '("x"))))
      (expect (string= "bad value" (toml-encoding-error-message condition)))
      (expect (equal '("x") (toml-encoding-error-path condition))))))
