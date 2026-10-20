;;;; t/conditions-test.lisp
(in-package #:cl-toml-kit/test)

(describe "TOML conditions"
  (it "normalizes parse and encoding constructor inputs"
    (let ((parse-error (make-condition 'toml-parse-error
                                       :expected "value"
                                       :path '("root" "child")))
          (encoding-error (make-condition 'toml-encoding-error
                                          :message "bad"
                                          :path '("root" "child"))))
      (expect (and (string= "value" (toml-parse-error-expected parse-error))
                   (equal '("root" "child")
                          (toml-parse-error-path parse-error))))
      (expect (and (string= "bad" (toml-encoding-error-message encoding-error))
                   (equal '("root" "child")
                          (toml-encoding-error-path encoding-error))))))
  (it "constructs parse diagnostics"
    (let ((condition (make-condition 'toml-parse-error
                                     :source-name "input"
                                     :path (list 'key "name")
                                     :expected "expected"
                                     :context "context"
                                     :text (make-string 256 :initial-element #\x))))
      (expect (and (equal (list 'key "name")
                          (toml-parse-error-path condition))
                   (string= "expected" (toml-parse-error-expected condition))
                   (string= "context" (toml-parse-error-context condition))))
      (expect (<= (length (toml-parse-error-text condition)) 256))))
  (it "reports every parse diagnostic accessor"
    (let ((condition (make-condition 'toml-parse-error
                                     :source-name "input.toml"
                                     :position 4 :line 2 :column 3
                                     :path '("root" 1) :expected "value"
                                     :context "table" :text "x =")))
      (expect (and (string= "input.toml"
                            (toml-parse-error-source-name condition))
                   (= 4 (toml-parse-error-position condition))
                   (= 2 (toml-parse-error-line condition))))
      (expect (and (= 3 (toml-parse-error-column condition))
                   (equal '("root" 1) (toml-parse-error-path condition))
                   (string= "value" (toml-parse-error-expected condition))))
      (expect (and (string= "table" (toml-parse-error-context condition))
                   (string= "x =" (toml-parse-error-text condition))
                   (plusp (length (format nil "~A" condition)))))))
  (it "constructs an encoding condition with bounded path values"
    (let ((condition (make-condition 'toml-encoding-error
                                     :message (make-string 256 :initial-element #\m)
                                     :path (list (make-string 64 :initial-element #\p)))))
      (expect (<= (length (toml-encoding-error-message condition)) 256))
      (expect (<= (length (first (toml-encoding-error-path condition))) 64))))
  (it "bounds encoding path components and aggregate report length"
    (let* ((path (append (list (make-string 10000 :initial-element #\p)
                               (ash 1 100000)
                               (concatenate 'string
                                            "control"
                                            (coerce (list #\Newline #\Tab #\Return #\Null)
                                                    'string)))
                         (make-list 100 :initial-element "component")))
           (condition (cl-toml-kit::make-toml-encoding-error :message "bad" :path path))
           (normalized (toml-encoding-error-path condition))
           (canonical-path (cl-toml-kit::%diagnostic-path-report-string normalized))
           (hostile-size
             (let ((*print-length* 1)
                   (*print-level* 1)
                   (*print-escape* nil))
               (cl-toml-kit::%diagnostic-path-rendered-size normalized)))
           (rendered-path
             (let ((*print-length* 1)
                   (*print-level* 1)
                   (*print-escape* nil))
               (cl-toml-kit::%diagnostic-path-report-string normalized)))
           (report
             (let ((*print-length* 1)
                   (*print-level* 1)
                   (*print-escape* nil))
               (format nil "~A" condition))))
      (expect (<= (cl-toml-kit::%diagnostic-path-rendered-size (first normalized))
                  cl-toml-kit::+toml-diagnostic-path-component-limit+))
      (expect (search "..." (first normalized)))
      (expect (string= "integer" (second normalized)))
      (expect (search "control" rendered-path))
      (expect (notany (lambda (character)
                        (member character '(#\Newline #\Tab #\Return #\Null)))
                      rendered-path))
      (expect (eq :... (car (last normalized))))
      (expect (= hostile-size (length canonical-path)))
      (expect (string= canonical-path rendered-path))
      (expect (<= (length canonical-path)
                  cl-toml-kit::+toml-diagnostic-path-limit+))
      (expect (<= (length report)
              (+ (length "TOML encode error at ")
                 cl-toml-kit::+toml-diagnostic-path-limit+
                 (length ": ")
                 (length "bad"))))
      (expect (search canonical-path report))))
  (it "reports encoding message and path"
    (let ((condition (make-condition 'toml-encoding-error
                                     :message "bad value" :path '("x"))))
      (expect (string= "bad value" (toml-encoding-error-message condition)))
      (expect (equal '("x") (toml-encoding-error-path condition)))
      (expect (plusp (length (format nil "~A" condition)))))))
