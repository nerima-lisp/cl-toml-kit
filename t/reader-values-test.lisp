(in-package #:cl-toml-kit/test)

(defun %reader-nan-p (value)
  (and (floatp value) (sb-ext:float-nan-p value)))

(defun %reader-float= (left right)
  (and (floatp left) (floatp right)
       (if (sb-ext:float-nan-p right)
           (sb-ext:float-nan-p left)
           (= left right))))

(defun %reader-date-text (value)
  (cond
    ((cl-date-kit:offset-date-time-p value)
     (cl-date-kit:format-offset-date-time value :profile :rfc3339))
    ((cl-date-kit:local-date-time-p value)
     (cl-date-kit:format-local-date-time value :profile :rfc3339))
    ((cl-date-kit:local-date-p value)
     (cl-date-kit:format-local-date value))
    ((cl-date-kit:local-time-p value)
     (cl-date-kit:format-local-time value :profile :rfc3339))))

(describe "TOML reader scalar values"
  (it-each (("0" 0)
            ("9223372036854775807" 9223372036854775807)
            ("-9223372036854775808" -9223372036854775808)
            ("0xDEAD_BEEF" 3735928559)
            ("0o755" 493)
            ("0b1101_0101" 213)
            ("1_000_000" 1000000))
      "reads integer ~S as ~S"
      (text expected)
    (expect (equal (gethash "value" (parse (format nil "value = ~A" text)))
                   expected)))
  (it-each (("0.1" 0.1d0)
            ("1e308" 1.0d308)
            ("-0.0" -0.0d0))
      "reads float ~S as the expected double float"
      (text expected)
    (expect (%reader-float= (gethash "value"
                                     (parse (format nil "value = ~A" text)))
                            expected)))
  (it "reads the smallest subnormal double float"
    (expect (= least-positive-double-float
               (gethash "value" (parse "value = 5e-324")))))
  (it "reads positive and negative infinity"
    (expect (= sb-ext:double-float-positive-infinity
               (gethash "value" (parse "value = inf"))))
    (expect (= sb-ext:double-float-negative-infinity
               (gethash "value" (parse "value = -inf")))))
  (it-each (("nan") ("+nan") ("-nan"))
      "reads ~S as NaN"
      (text)
    (expect (%reader-nan-p (gethash "value" (parse (format nil "value = ~A" text))))))
  (it-each (("value = 'C:\\tmp\\file'" "C:\\tmp\\file"))
      "reads string input ~S as ~S"
      (text expected)
    (expect (string= (gethash "value" (parse text)) expected)))
  (it "reads all basic string escapes"
    (let* ((source "value = \"\\b\\t\\n\\f\\r\\e\\\"\\\\\\x41\\u0042\\U00000043\"")
           (expected (format nil "~C~C~C~C~C~C~C~CABC"
                             #\Backspace #\Tab #\Newline #\Page #\Return #\Escape
                             #\" #\\)))
      (expect (string= expected (gethash "value" (parse source))))))
  (it "reads multiline strings and removes the initial newline"
    (let ((source (format nil "value = \"\"\"~%first~%second\"\"\"")))
      (expect (string= (format nil "first~%second"
                               ) (gethash "value" (parse source))))))
  (it "reads a multiline line-ending backslash"
    (let ((source (format nil "value = \"\"\"first \\~%second\"\"\"")))
      (expect (string= "first second" (gethash "value" (parse source))))))
  (it-each (("1979-05-27T07:32:00Z" "1979-05-27T07:32:00Z")
            ("1979-05-27t07:32:00z" "1979-05-27T07:32:00Z")
            ("1979-05-27 07:32" "1979-05-27T07:32:00")
            ("1979-05-27T07:32:00" "1979-05-27T07:32:00")
            ("1979-05-27" "1979-05-27")
            ("07:32" "07:32:00"))
      "reads datetime input ~S in normalized form ~S"
      (text expected)
    (expect (string= (%reader-date-text
                      (gethash "value" (parse (format nil "value = ~A" text))))
                     expected))))

(describe "TOML reader stream and document values"
  (it "reads a character stream"
    (with-input-from-string (stream (format nil "answer = 42~%"))
      (expect (= 42 (gethash "answer" (parse stream))))))
  (it-each (("" 0) ("# only a comment" 0) ("" 0))
      "reads empty document input ~S as an empty table"
      (text expected-count)
    (expect (= expected-count (hash-table-count (parse text)))))
  (it "accepts CRLF between document lines"
    (let ((table (parse (format nil "a = 1~C~Cb = 2~C~C"
                                #\Return #\Newline #\Return #\Newline))))
      (expect (= 1 (gethash "a" table)))
      (expect (= 2 (gethash "b" table)))))
  (it "reads dotted keys and nested table values"
    (let ((table (parse (format nil
                               "fruit.name = \"apple\"~%[fruit.physical]~%color = \"red\"~%"))))
      (expect (string= "apple" (gethash "name" (gethash "fruit" table))))
      (expect (string= "red" (gethash "color"
                                        (gethash "physical" (gethash "fruit" table)))))))
  (it "reads tables, array tables, and inline tables"
    (let ((table (parse
                  (with-output-to-string (stream)
                    (format stream "[owner]~%name = \"Tom\"~%")
                    (format stream "[[products]]~%name = \"A\"~%")
                    (format stream "[[products]]~%name = \"B\"~%")
                    (format stream "config = { enabled = true, count = 2 }~%")))))
      (expect (string= "Tom" (gethash "name" (gethash "owner" table))))
      (expect (= 2 (length (gethash "products" table))))
      (expect (eql t (gethash "enabled" (gethash "config" (aref (gethash "products" table) 1))))))))
