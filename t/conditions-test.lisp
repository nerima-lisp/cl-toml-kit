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
  (it "reports default and normalized value-model messages"
    (let* ((default-error (make-condition 'toml-value-model-error))
           (non-string-error (make-condition 'toml-value-model-error :message 42)))
      (expect
       (string= "Invalid TOML value model"
                (format nil "~A" default-error)))
      (expect
       (string= "integer"
                (format nil "~A" non-string-error)))))
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
  (it "escapes noninteger parse coordinates in full reports"
    (let* ((condition
             (make-condition 'toml-parse-error
                             :line (concatenate 'string
                                                "line"
                                                (string #\Newline)
                                                "break")
                             :column (concatenate 'string
                                                  "column"
                                                  (string #\Tab)
                                                  "break")
                             :position (concatenate 'string
                                                    "position"
                                                    (string (code-char 0))
                                                    "break")))
           (report (format nil "~A" condition))
           (integer-condition
             (make-condition 'toml-parse-error
                             :line 10 :column 12 :position 14))
           (integer-report
             (let ((*print-base* 16)
                   (*print-radix* t))
               (format nil "~A" integer-condition))))
      (expect
       (string=
        "TOML parse error at line line\\nbreak, column column\\tbreak (position position\\u0000break)"
        report))
      (expect
       (string= "TOML parse error at line 10, column 12 (position 14)"
                integer-report))))
  (it "reports every parse diagnostic accessor"
    (let* ((controls
            (coerce
             (list (code-char 0)
                   (code-char #x1B)
                   (code-char #x80)
                   (code-char #x9F)
                   (code-char #x7F))
             'string))
           (escape-sequence "\\u0000\\u001B\\u0080\\u009F\\u007F")
           (raw-source-name
            (concatenate 'string
                         "input.toml"
                         controls
                         (make-string 300 :initial-element #\x)))
           (condition
            (cl-toml-kit::make-toml-parse-error :source-name
                                                raw-source-name
                                                :position
                                                4
                                                :line
                                                2
                                                :column
                                                3
                                                :path
                                                '("root" 1)
                                                :expected
                                                "value"
                                                :context
                                                "table"
                                                :text
                                                "x ="))
           (source-name (toml-parse-error-source-name condition))
           (direct-condition
            (make-condition 'toml-parse-error :source-name raw-source-name))
           (direct-report (format nil "~A" direct-condition))
           (parser-condition
            (handler-case (progn
                            (parse (concatenate 'string "a = @" controls)
                                   :source-name
                                   (concatenate 'string "example.toml" controls))
                            nil)
              (toml-parse-error (parse-error)
                parse-error)))
           (parser-report
            (and parser-condition (format nil "~A" parser-condition)))
           (raw-expected
            (concatenate 'string
                         "expected:"
                         controls
                         (make-string 200 :initial-element #\e)))
           (expected-condition
            (cl-toml-kit::make-toml-parse-error :expected raw-expected))
           (expected-text (toml-parse-error-expected expected-condition))
           (boundary-source-name
            (concatenate 'string
                         (make-string 251 :initial-element #\b)
                         (string (code-char 0))
                         "tail"))
           (boundary-condition
            (make-condition 'toml-parse-error :source-name boundary-source-name))
           (boundary-report (format nil "~A" boundary-condition))
           (empty-condition (cl-toml-kit::make-toml-parse-error)))
      (expect
       (and (string= "input.toml" (subseq source-name 0 10))
            (search escape-sequence source-name)
            (<= (length source-name) cl-toml-kit::+toml-diagnostic-limit+)))
      (expect
       (notany
        (lambda (character)
          (let ((code (char-code character)))
            (or (< code 32) (<= #x7F code #x9F))))
        source-name))
      (expect
       (notany
        (lambda (character)
          (let ((code (char-code character)))
            (or (< code 32) (<= #x7F code #x9F))))
        direct-report))
      (expect (search escape-sequence direct-report))
      (expect
       (and (= 4 (toml-parse-error-position condition))
            (= 2 (toml-parse-error-line condition))
            (= 3 (toml-parse-error-column condition))
            (equal '("root" 1) (toml-parse-error-path condition))
            (string= "value" (toml-parse-error-expected condition))
            (string= "table" (toml-parse-error-context condition))
            (string= "x =" (toml-parse-error-text condition))))
      (expect parser-condition)
      (expect (search escape-sequence parser-report))
      (expect
       (notany
        (lambda (character)
          (let ((code (char-code character)))
            (or (< code 32) (<= #x7F code #x9F))))
        parser-report))
      (expect
       (and (string= "expected:" (subseq expected-text 0 9))
            (search escape-sequence expected-text)
            (<= (length expected-text) 128)
            (notany
             (lambda (character)
               (let ((code (char-code character)))
                 (or (< code 32) (<= #x7F code #x9F))))
             expected-text)))
      (expect
       (and (search (make-string 251 :initial-element #\b) boundary-report)
            (not (search "\\u0000" boundary-report))
            (not (search "tail" boundary-report))
            (notany
             (lambda (character)
               (let ((code (char-code character)))
                 (or (< code 32) (<= #x7F code #x9F))))
             boundary-report)))
      (expect
       (and (null (toml-parse-error-source-name empty-condition))
            (null (toml-parse-error-expected empty-condition))))))
  (it "reports pathname source names in full parser errors"
    (let* ((condition
            (handler-case (progn
                            (parse "a = @" :source-name #p"/x/y.toml")
                            nil)
              (toml-parse-error (parse-error)
                parse-error)))
           (expected-report
            "TOML parse error in /x/y.toml at line 1, column 5 (position 4); expected integer digit"))
      (expect condition)
      (expect (string= expected-report (format nil "~A" condition)))))
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
  (it "renders diagnostic controls escaped in error messages"
    (let* ((controls
            (coerce
             (list (code-char 0)
                   (code-char #x1B)
                   (code-char #x80)
                   (code-char #x9F)
                   (code-char #x7F))
             'string))
           (message (concatenate 'string "bad" controls))
           (encoding-error
            (make-condition 'toml-encoding-error :message message :path '("x")))
           (value-error
            (make-condition 'toml-value-model-error :message message))
           (format-error
            (make-condition 'toml-format-preservation-error :message message))
           (nil-encoding-error
            (make-condition 'toml-encoding-error :message nil))
           (nil-format-error
            (make-condition 'toml-format-preservation-error :message nil))
           (encoding-report (format nil "~A" encoding-error))
           (value-report (format nil "~A" value-error))
           (format-report (format nil "~A" format-error)))
      (expect
       (string=
        "TOML encode error at (\"x\"): bad\\u0000\\u001B\\u0080\\u009F\\u007F"
        encoding-report))
      (expect (string= "bad\\u0000\\u001B\\u0080\\u009F\\u007F" value-report))
      (expect
       (string=
        "TOML format-preserving edit error: bad\\u0000\\u001B\\u0080\\u009F\\u007F"
        format-report))
      (expect
       (string= "TOML encode error: NIL" (format nil "~A" nil-encoding-error)))
      (expect
       (string= "TOML format-preserving edit error: NIL"
                (format nil "~A" nil-format-error))))))
