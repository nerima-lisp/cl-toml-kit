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
  (it "sets parse error path, expected text, and context"
    (let ((condition (make-condition (quote toml-parse-error)
                                     :path (list "root" "child")
                                     :expected "expected"
                                     :context "context")))
      (expect (equal (list "root" "child")
                     (toml-parse-error-path condition)))
      (expect (string= "expected"
                       (toml-parse-error-expected condition)))
      (expect (string= "context"
                       (toml-parse-error-context condition)))))
  (it "truncates text in normalized parse errors"
    (let ((condition
            (cl-toml-kit::make-toml-parse-error
             :text (make-string 300 :initial-element (code-char 120)))))
      (expect (= (length (toml-parse-error-text condition)) 256))))
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
  (it "normalizes and escapes constructed source names"
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
            (cl-toml-kit::make-toml-parse-error :source-name raw-source-name))
           (source-name (toml-parse-error-source-name condition))
           (direct-condition
            (make-condition 'toml-parse-error :source-name raw-source-name))
           (direct-report (format nil "~A" direct-condition)))
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
       (and (notany
             (lambda (character)
               (let ((code (char-code character)))
                 (or (< code 32) (<= #x7F code #x9F))))
             direct-report)
            (search escape-sequence direct-report)))))
  (it "reports parse diagnostic coordinates"
    (let ((condition
            (cl-toml-kit::make-toml-parse-error
             :position 4 :line 2 :column 3)))
      (expect (= 4 (toml-parse-error-position condition)))
      (expect (= 2 (toml-parse-error-line condition)))
      (expect (= 3 (toml-parse-error-column condition)))))
  (it "reports parse diagnostic paths and expected text"
    (let ((condition
            (cl-toml-kit::make-toml-parse-error
             :path '("root" 1)
             :expected "value")))
      (expect (equal '("root" 1) (toml-parse-error-path condition)))
      (expect (string= "value" (toml-parse-error-expected condition)))))
  (it "reports parse diagnostic context and text"
    (let ((condition
            (cl-toml-kit::make-toml-parse-error
             :context "table"
             :text "x =")))
      (expect (string= "table" (toml-parse-error-context condition)))
      (expect (string= "x =" (toml-parse-error-text condition)))))
  (it "escapes source names from parser errors"
    (let* ((controls
            (coerce
             (list (code-char 0)
                   (code-char #x1B)
                   (code-char #x80)
                   (code-char #x9F)
                   (code-char #x7F))
             'string))
           (escape-sequence "\\u0000\\u001B\\u0080\\u009F\\u007F")
           (condition
            (handler-case
                (progn
                  (parse (concatenate 'string "a = @" controls)
                         :source-name
                         (concatenate 'string "example.toml" controls))
                  nil)
              (toml-parse-error (parse-error) parse-error)))
           (report (and condition (format nil "~A" condition))))
      (expect condition)
      (expect (search escape-sequence report))
      (expect
       (notany
        (lambda (character)
          (let ((code (char-code character)))
            (or (< code 32) (<= #x7F code #x9F))))
        report))))
  (it "truncates and escapes parse expected text"
    (let* ((controls
             (coerce
              (list (code-char 0)
                    (code-char #x1B)
                    (code-char #x80)
                    (code-char #x9F)
                    (code-char #x7F))
              'string))
           (escape-sequence "\\u0000\\u001B\\u0080\\u009F\\u007F")
           (raw-expected
             (concatenate 'string
                          "expected:"
                          controls
                          (make-string 200 :initial-element #\e)))
           (condition
             (cl-toml-kit::make-toml-parse-error :expected raw-expected))
           (expected-text (toml-parse-error-expected condition)))
      (expect
       (and (string= "expected:" (subseq expected-text 0 9))
            (search escape-sequence expected-text)
            (= (length expected-text) 128)
            (notany
             (lambda (character)
               (let ((code (char-code character)))
                 (or (< code 32) (<= #x7F code #x9F))))
             expected-text)))))
  (it "truncates a source name at a control boundary"
    (let* ((boundary-source-name
            (concatenate (quote string)
                         (make-string 251 :initial-element #\b)
                         (string (code-char 0))
                         "tail"))
           (condition
            (make-condition (quote toml-parse-error)
                            :source-name boundary-source-name))
           (report (format nil "~A" condition)))
      (expect
       (string=
        (format nil
                "TOML parse error in ~A at line 1, column 1 (position 0)"
                (subseq boundary-source-name 0 251))
        report))))
  (it "leaves source name and expected text unset when omitted"
    (let ((condition (cl-toml-kit::make-toml-parse-error)))
      (expect
       (and (null (toml-parse-error-source-name condition))
            (null (toml-parse-error-expected condition))))))
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
    (let ((condition (cl-toml-kit::make-toml-encoding-error :message (make-string 300 :initial-element #\m) :path (list (make-string 100 :initial-element #\p)))))
      (expect (= (length (toml-encoding-error-message condition)) 256))
      (expect (<= (length (first (toml-encoding-error-path condition))) 64))))
  (it "bounds encoding path component representations"
    (let* ((path (append (list (make-string 10000 :initial-element #\p)
                             (ash 1 100000)
                             (concatenate 'string
                                          "control"
                                          (coerce (list #\Newline #\Tab #\Return #\Null)
                                                  'string)))
                       (make-list 100 :initial-element "component")))
           (normalized (toml-encoding-error-path
                        (cl-toml-kit::make-toml-encoding-error
                         :message "bad" :path path))))
      (expect
       (and (<= (cl-toml-kit::%diagnostic-path-rendered-size (first normalized))
                cl-toml-kit::+toml-diagnostic-path-component-limit+)
            (search "..." (first normalized))))
      (expect (string= "integer" (second normalized)))
      (expect (eq :... (car (last normalized))))))
  (it "renders control-free paths consistently under print bindings"
    (let* ((path
             (append
              (list (make-string 10000 :initial-element #\p)
                    (ash 1 100000)
                    (concatenate 'string
                                 "control"
                                 (coerce (list #\Newline #\Tab #\Return #\Null)
                                         'string)))
              (make-list 100 :initial-element "component")))
           (normalized
             (toml-encoding-error-path
              (cl-toml-kit::make-toml-encoding-error :message "bad" :path path)))
           (canonical-path
             (cl-toml-kit::%diagnostic-path-report-string normalized))
           (hostile-size
             (let ((*print-length* 1)
                   (*print-level* 1)
                   (*print-escape* nil))
               (cl-toml-kit::%diagnostic-path-rendered-size normalized)))
           (rendered-path
             (let ((*print-length* 1)
                   (*print-level* 1)
                   (*print-escape* nil))
               (cl-toml-kit::%diagnostic-path-report-string normalized))))
      (expect
       (and (search "control" rendered-path)
            (notany (lambda (character)
                      (member character '(#\Newline #\Tab #\Return #\Null)))
                    rendered-path)))
      (expect (= hostile-size (length canonical-path)))
      (expect (string= canonical-path rendered-path))))
  (it "bounds aggregate encoding report length"
    (let* ((path (append (list (make-string 10000 :initial-element #\p)
                             (ash 1 100000)
                             (concatenate 'string
                                          "control"
                                          (coerce (list #\Newline #\Tab #\Return #\Null)
                                                  'string)))
                       (make-list 100 :initial-element "component")))
           (condition
            (cl-toml-kit::make-toml-encoding-error :message "bad" :path path))
           (normalized (toml-encoding-error-path condition))
           (canonical-path
            (cl-toml-kit::%diagnostic-path-report-string normalized))
           (report
            (let ((*print-length* 1)
                  (*print-level* 1)
                  (*print-escape* nil))
              (format nil "~A" condition))))
      (expect (<= (length canonical-path)
                  cl-toml-kit::+toml-diagnostic-path-limit+))
      (expect
       (<= (length report)
           (+ (length "TOML encode error at ")
              cl-toml-kit::+toml-diagnostic-path-limit+
              (length ": ")
              (length "bad"))))
      (expect (search canonical-path report))))
  (it "escapes controls in encoding and value-model messages"
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
            (make-condition 'toml-value-model-error :message message)))
      (expect
       (string=
        "TOML encode error at (\"x\"): bad\\u0000\\u001B\\u0080\\u009F\\u007F"
        (format nil "~A" encoding-error)))
      (expect
       (string= "bad\\u0000\\u001B\\u0080\\u009F\\u007F"
                (format nil "~A" value-error)))))
  (it "escapes controls in format-preservation messages"
    (let* ((controls
            (coerce
             (list (code-char 0)
                   (code-char #x1B)
                   (code-char #x80)
                   (code-char #x9F)
                   (code-char #x7F))
             'string))
           (message (concatenate 'string "bad" controls))
           (format-error
            (make-condition 'toml-format-preservation-error :message message)))
      (expect
       (string=
        "TOML format-preserving edit error: bad\\u0000\\u001B\\u0080\\u009F\\u007F"
        (format nil "~A" format-error)))))
  (it "reports nil encoding and format-preservation messages"
    (let ((encoding-error
            (make-condition 'toml-encoding-error :message nil))
          (format-error
            (make-condition 'toml-format-preservation-error :message nil)))
      (expect
       (string= "TOML encode error: NIL" (format nil "~A" encoding-error)))
      (expect
       (string= "TOML format-preserving edit error: NIL"
                (format nil "~A" format-error)))))
  (it "escapes raw surrogates in diagnostic reports"
    (let* ((surrogates (coerce (list (code-char #xD800)
                                    (code-char #xDFFF))
                               'string))
           (text-condition
             (make-condition 'toml-value-model-error
                             :message (concatenate 'string "bad" surrogates)))
           (path-condition
             (cl-toml-kit::make-toml-encoding-error
              :message "bad"
              :path (list (concatenate 'string "key" surrogates)))))
      (expect
       (string= "bad\\uD800\\uDFFF"
                (format nil "~A" text-condition)))
      (expect
       (string=
        "TOML encode error at (\"key\\\\uD800\\\\uDFFF\"): bad"
        (format nil "~A" path-condition))))))
