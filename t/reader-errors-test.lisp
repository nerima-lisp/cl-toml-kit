(in-package #:cl-toml-kit/test)

(defun %reader-error (text)
  (handler-case (progn (parse text) nil)
    (toml-parse-error (condition) condition)))

(describe "TOML reader errors"
  (it "rejects nested arrays and inline tables at MAX-DEPTH"
    (let ((array-error (handler-case
                           (parse "value = [[[1]]]" :max-depth 2)
                         (toml-parse-error (condition) condition)))
          (table-error (handler-case
                           (parse "value = {a = {b = {c = 1}}}" :max-depth 2)
                         (toml-parse-error (condition) condition))))
      (expect (typep array-error 'toml-parse-error))
      (expect (string= "shallower nesting"
                       (toml-parse-error-expected array-error)))
      (expect (typep table-error 'toml-parse-error))
      (expect (string= "shallower nesting"
                       (toml-parse-error-expected table-error)))))
  (it-each (("value = 9223372036854775808")
            ("value = -9223372036854775809")
            ("value = 01")
            ("value = 1__0")
            ("value = 0x")
            ("value = 0b102"))
      "reports the invalid value ~S with source coordinates"
      (text)
    (let ((condition (%reader-error text)))
      (expect (typep condition 'toml-parse-error))
      (expect (plusp (toml-parse-error-line condition)))
      (expect (plusp (toml-parse-error-column condition)))))
  (it "rejects a floating-point overflow with a TOML parse error"
    (expect (signals toml-parse-error (parse "value = 1e309"))))
  (it "rejects a fractional minute with a TOML parse error"
    (expect (signals toml-parse-error (parse "value = 07:32.5"))))
  (it-each ((#.(concatenate 'string "a = 1" (string #\Return)) 1 6)
            (#.(concatenate 'string "a = " (string (code-char 1))) 1 5)
            ("t/fixtures/toml-test/invalid/encoding/bad-utf8-at-end.toml" 5 11))
      "reports a concrete position for malformed input ~S"
      (input expected-line expected-column)
    (let ((condition (handler-case
                         (if (search ".toml" input)
                             (parse-file input)
                             (parse input))
                       (toml-parse-error (error) error))))
      (expect (typep condition 'toml-parse-error))
      (expect (= expected-line (toml-parse-error-line condition)))
      (expect (= expected-column (toml-parse-error-column condition)))))
  (it-each ((#.(format nil "a = 1~%b = 2~%c = 3~%a = 4"))
            (#.(format nil "[a]~%x = 1~%[a]~%y = 2"))
            (#.(format nil "[[items]]~%x = 1~%[[items]]~%x = 2~%[items]~%y = 3"))
            ("x = { a = 1, a = 2 }"))
      "reports duplicate definitions in ~S with source coordinates"
      (text)
    (let ((condition (%reader-error text)))
      (expect (typep condition 'toml-parse-error))
      (expect (plusp (toml-parse-error-line condition)))
      (expect (plusp (toml-parse-error-column condition)))))
  (it "includes a readable source name and diagnostic text"
    (let ((condition (handler-case
                        (parse "a = @" :source-name "example.toml")
                      (toml-parse-error (error) error))))
      (expect (string= "example.toml"
                       (toml-parse-error-source-name condition)))
      (expect (plusp (length (toml-parse-error-text condition))))
      (expect (search "line" (princ-to-string condition))))))
