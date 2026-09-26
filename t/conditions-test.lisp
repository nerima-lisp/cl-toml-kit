;;;; t/conditions-test.lisp
(in-package #:cl-toml-kit/test)

(describe "TOML conditions"
  (it "constructs bounded and escaped diagnostics"
    (let ((condition (make-toml-parse-error
                      :source-name "input"
                      :path (list 'key "name")
                      :expected (format nil "line~%tab~C" #\Tab)
                      :context (format nil "context~C" #\Return)
                      :text (make-string 300 :initial-element #\x))))
      (expect (equal (list "KEY" "name")
                     (toml-parse-error-path condition)))
      (expect (search "line\\n" (toml-parse-error-expected condition)))
      (expect (search "context\\r" (toml-parse-error-context condition)))
      (expect (<= (length (toml-parse-error-text condition)) 256))))
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
      (expect (plusp (length (format nil "~A" condition))))))
  (it "constructs an encoding condition with bounded path values"
    (let ((condition (make-toml-encoding-error
                      :message (make-string 300 :initial-element #\m)
                      :path (list (make-string 100 :initial-element #\p)))))
      (expect (<= (length (toml-encoding-error-message condition)) 256))
      (expect (<= (length (first (toml-encoding-error-path condition))) 64))))
  (it "reports encoding message and path"
    (let ((condition (make-condition 'toml-encoding-error
                                     :message "bad value" :path '("x"))))
      (expect (string= "bad value" (toml-encoding-error-message condition)))
      (expect (equal '("x") (toml-encoding-error-path condition)))
      (expect (plusp (length (format nil "~A" condition)))))))
