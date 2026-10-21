(in-package #:cl-toml-kit/test)

(defun %reader-number-error (text &key source-name)
  (handler-case (progn (parse text :source-name source-name) nil)
    (toml-parse-error (condition) condition)))

(describe "reader number security"
  (it "reports numeric diagnostic text and token offset through parse"
    (let ((condition (%reader-number-error "items = [1__0]")))
      (expect (string= "digit between underscores"
                       (toml-parse-error-expected condition)))
      (expect (= 11 (toml-parse-error-position condition)))))
  (it "reports CRLF coordinates and source name for numeric parse errors"
    (let ((condition
            (%reader-number-error
             (format nil "a = 1~C~Citems = [0x]" #\Return #\Newline)
             :source-name "numbers.toml")))
      (expect (string= "integer digit"
                       (toml-parse-error-expected condition)))
      (expect (= 18 (toml-parse-error-position condition)))
      (expect (= 2 (toml-parse-error-line condition)))
      (expect (= 12 (toml-parse-error-column condition)))
      (expect (string= "numbers.toml"
                       (toml-parse-error-source-name condition)))
      (expect (search "integer digit"
                      (toml-parse-error-text condition)))))
  (it "reports nested path and source metadata through parse"
    (let* ((*toml-max-nesting-depth* 1)
           (condition
             (handler-case
                 (progn
                   (parse "[a.b.c]" :source-name "numbers.toml")
                   nil)
               (toml-parse-error (error) error))))
      (expect (typep condition 'toml-parse-error))
      (expect (equal '("a") (toml-parse-error-path condition)))
      (expect (string= "TOML nesting depth limit exceeded"
                       (toml-parse-error-expected condition)))
      (expect (string= "numbers.toml"
                       (toml-parse-error-source-name condition)))
      (expect (search "TOML nesting depth limit exceeded"
                      (toml-parse-error-text condition)))))
  (it "rejects a ten-thousand-digit integer at the token limit"
    (let* ((condition
             (%reader-number-error
              (concatenate 'string "value = "
                           (make-string 10000 :initial-element #\9))))
           (expected
             (nth-value 1
                        (cl-toml-kit::%toml-limit :number-token-length))))
      (expect (typep condition 'toml-parse-error))
      (expect (string= expected (toml-parse-error-expected condition)))
      (expect (= 8 (toml-parse-error-position condition)))))
  (it "honors the configured number-token limit"
    (let* ((*toml-max-number-token-length* 4)
           (condition (%reader-number-error "v = 12345"))
           (expected
             (nth-value 1
                        (cl-toml-kit::%toml-limit :number-token-length))))
      (expect (typep condition 'toml-parse-error))
      (expect (string= expected (toml-parse-error-expected condition)))
      (expect (= 4 (toml-parse-error-position condition)))))
  (it "honors the configured number-token limit for floats"
    (let* ((*toml-max-number-token-length* 4)
           (condition (%reader-number-error "v = 1.234"))
           (expected
             (nth-value 1
                        (cl-toml-kit::%toml-limit :number-token-length))))
      (expect (typep condition 'toml-parse-error))
      (expect (string= expected (toml-parse-error-expected condition)))
      (expect (= 4 (toml-parse-error-position condition)))))
  (it-each (("value = 1e999999999999999999")
            ("value = 1e-999999999999999999")
            ("value = 1.7976931348623159e308"))
      "rejects non-representable finite floats in ~S"
      (text)
    (let* ((condition (%reader-number-error text))
           (expected
             (cl-toml-kit::%toml-reader-error-message :representable-finite-float)))
      (expect (typep condition 'toml-parse-error))
      (expect (string= expected (toml-parse-error-expected condition)))
      (expect (= 8 (toml-parse-error-position condition)))))
  (it "preserves subnormal and compensated finite values"
    (let* ((subnormal (gethash "value" (parse "value = 5e-324")))
           (source
             (concatenate 'string "value = "
                          (make-string 200 :initial-element #\9)
                          "e-400"))
           (compensated (gethash "value" (parse source))))
      (expect (= least-positive-double-float subnormal))
      (expect (toml-float-p compensated))
      (expect (plusp compensated))))
  (it "reports malformed date fields and positions across CRLF and CRXLF"
    (dolist (text '("value = 1979-xx-27"
                    "value = 1979-05-xx"))
      (let ((condition (%reader-number-error text)))
        (expect (typep condition 'toml-parse-error))
        (expect (= 8 (toml-parse-error-position condition)))
        (expect (= 1 (toml-parse-error-line condition)))
        (expect (= 9 (toml-parse-error-column condition)))
        (expect
         (string=
          (cl-toml-kit::%toml-reader-error-message :valid-date-or-time)
          (toml-parse-error-expected condition)))))
    (flet ((expect-position (source expected-position expected-line expected-column)
             (let ((condition (%reader-number-error source)))
               (expect (typep condition 'toml-parse-error))
               (expect (= expected-position
                          (toml-parse-error-position condition)))
               (expect (= expected-line (toml-parse-error-line condition)))
               (expect (= expected-column
                          (toml-parse-error-column condition))))))
      (expect-position (format nil "# comment~C~Cvalue = 1__2" #\Return #\Newline) 21 2 11)
      (expect-position (format nil "# first~CX~Cvalue = 1__2" #\Return #\Newline) 7 1 8))))
