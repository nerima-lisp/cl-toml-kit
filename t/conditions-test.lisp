;;;; t/conditions-test.lisp
(in-package #:cl-toml-kit/test)

(describe "TOML conditions"
  (it "normalizes parse and encoding constructor inputs"
    (let ((parse-error (cl-toml-kit::make-toml-parse-error
                        :expected (list :value) :path (list :root (list :child))))
          (encoding-error (cl-toml-kit::make-toml-encoding-error
                           :message (list :bad) :path (list :root (list :child)))))
      (expect (stringp (toml-parse-error-expected parse-error)))
      (expect (consp (toml-parse-error-path parse-error)))
      (expect (stringp (toml-encoding-error-message encoding-error)))
      (expect (consp (toml-encoding-error-path encoding-error)))))
  (it "constructs parse diagnostics"
    (let ((condition (make-condition 'toml-parse-error
                                     :source-name "input"
                                     :path (list 'key "name")
                                     :expected "expected"
                                     :context "context"
                                     :text (make-string 256 :initial-element #\x))))
      (expect (equal (list 'key "name")
                     (toml-parse-error-path condition)))
      (expect (string= "expected" (toml-parse-error-expected condition)))
      (expect (string= "context" (toml-parse-error-context condition)))
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
    (let ((condition (make-condition 'toml-encoding-error
                                     :message (make-string 256 :initial-element #\m)
                                     :path (list (make-string 64 :initial-element #\p)))))
      (expect (<= (length (toml-encoding-error-message condition)) 256))
      (expect (<= (length (first (toml-encoding-error-path condition))) 64))))
  (it "reports encoding message and path"
    (let ((condition (make-condition 'toml-encoding-error
                                     :message "bad value" :path '("x"))))
      (expect (string= "bad value" (toml-encoding-error-message condition)))
      (expect (equal '("x") (toml-encoding-error-path condition)))
      (expect (plusp (length (format nil "~A" condition)))))))
