(in-package #:cl-toml-kit/test)

(defun %reader-error (text)
  (handler-case (progn (parse text) nil)
    (toml-parse-error (condition) condition)))

(describe "reader number security"
  (it "preserves full error messages and source coordinates"
    (let ((condition
            (handler-case
                (cl-toml-kit::%error-at-message
                 (cl-toml-kit::%make-reader-state
                  :source (format nil "a~C~Cx = 1" #\Return #\Newline)
                  :length 8
                  :source-name "numbers.toml")
                 3
                 "custom numeric diagnostic"
                 '("items" "0"))
              (toml-parse-error (error) error))))
      (expect (string= "custom numeric diagnostic"
                       (toml-parse-error-expected condition)))
      (expect (and (= 3 (toml-parse-error-position condition))
                   (= 2 (toml-parse-error-line condition))
                   (= 1 (toml-parse-error-column condition))
                   (equal '("items" "0") (toml-parse-error-path condition))))
      (expect (and (string= "numbers.toml"
                            (toml-parse-error-source-name condition))
                   (search "custom numeric diagnostic"
                           (toml-parse-error-text condition))))))
  (it "rejects a ten-thousand-digit integer at the token limit"
    (let* ((condition
             (%reader-error
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
           (condition (%reader-error "v = 12345"))
           (expected
             (nth-value 1
                        (cl-toml-kit::%toml-limit :number-token-length))))
      (expect (typep condition 'toml-parse-error))
      (expect (string= expected (toml-parse-error-expected condition)))
      (expect (= 4 (toml-parse-error-position condition)))))
  (it "honors the configured number-token limit for floats"
    (let* ((*toml-max-number-token-length* 4)
           (condition (%reader-error "v = 1.234"))
           (expected
             (nth-value 1
                        (cl-toml-kit::%toml-limit :number-token-length))))
      (expect (typep condition 'toml-parse-error))
      (expect (string= expected (toml-parse-error-expected condition)))
      (expect (= 4 (toml-parse-error-position condition)))))
  (it-each (("value = 1e999999999999999999")
            ("value = 1e-999999999999999999"))
      "rejects out-of-range exponents in ~S"
      (text)
    (let* ((condition (%reader-error text))
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
      (expect (plusp compensated)))))
