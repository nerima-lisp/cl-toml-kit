(in-package #:cl-toml-kit/test)

(defun %reader-nan-p (value)
  (and (floatp value) (sb-ext:float-nan-p value)))

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

(defun %macroexpanded-defun (form name)
  (cond
    ((and (consp form)
          (symbolp (first form))
          (string= (symbol-name (first form)) "DEFUN")
          (eq (second form) name))
     form)
    ((consp form)
     (loop for part in form
           for definition = (%macroexpanded-defun part name)
           when definition
             return definition))))

(describe "TOML reader scalar values"
  (it-each (("0" 0)
            ("9223372036854775807" 9223372036854775807)
            ("-9223372036854775808" -9223372036854775808)
            ("0xDEAD_BEEF" 3735928559)
            ("0o755" 493)
            ("0b1101_0101" 213)
            ("1_000_000" 1000000)
            ("+1" 1))
      "reads integer ~S as ~S"
      (text expected)
    (expect (toml-test-value=
             expected
             (gethash "value" (parse (format nil "value = ~A" text))))))
  (it-each (("0.0" 0.0d0)
            ("-0.0" -0.0d0)
            ("0.1" 0.1d0)
            ("1e308" 1.0d308))
      "reads float ~S as the expected double float"
      (text expected)
    (expect (toml-test-value=
             expected
             (gethash "value" (parse (format nil "value = ~A" text))))))
  (it "reads the smallest subnormal double float"
    (expect (toml-test-value=
             least-positive-double-float
             (gethash "value" (parse "value = 5e-324")))))
  (it-each (("inf" :positive-infinity)
            ("+inf" :positive-infinity)
            ("-inf" :negative-infinity)
            ("nan" :nan)
            ("+nan" :nan)
            ("-nan" :nan))
      "reads special float token ~S"
      (text expected)
    (let ((value (gethash "value" (parse (format nil "value = ~A" text)))))
      (expect (case expected
                (:positive-infinity
                 (= sb-ext:double-float-positive-infinity value))
                (:negative-infinity
                 (= sb-ext:double-float-negative-infinity value))
                (:nan (%reader-nan-p value))))))
  (it-each (("literal string"
             "value = 'C:\\tmp\\file'"
             "C:\\tmp\\file")
            ("basic escapes"
             "value = \"\\b\\t\\n\\f\\r\\e\\\"\\\\\\x41\\u0042\\U00000043\""
             #.(format nil "~C~C~C~C~C~C~C~CABC"
                       #\Backspace #\Tab #\Newline #\Page #\Return #\Escape
                       #\" #\\))
            ("multiline initial newline"
             #.(format nil "value = \"\"\"~%first~%second\"\"\"")
             #.(format nil "first~%second"))
            ("multiline line-ending backslash"
             #.(format nil "value = \"\"\"first \\~%second\"\"\"")
             "first second"))
      "reads string case ~A"
      (case-name source expected)
    (expect (toml-test-value= expected (gethash "value" (parse source)))))
  (it "reads the largest Unicode scalar escape"
    (expect (string= (string (code-char #x10FFFF))
                     (gethash "value" (parse "value = \"\\U0010FFFF\"")))))
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
      (expect (toml-test-value= 42 (gethash "answer" (parse stream))))))
  (it-each (("" 0) ("# only a comment" 0))
      "reads empty document input ~S as an empty table"
      (text expected-count)
    (expect (toml-test-value= expected-count
             (hash-table-count (parse text)))))
  (it-each (("empty array" "value = []" #())
            ("trailing comma" "value = [1,]" #(1))
            ("two entries" "value = [1, 2]" #(1 2)))
      "reads array case ~A"
      (case-name source expected)
    (expect (toml-test-value= expected (gethash "value" (parse source)))))
  (it-each (("empty inline table" "value = {}" 0 nil)
            ("single inline entry" "value = { answer = 42 }" 1 42))
      "reads inline table case ~A"
      (case-name source expected-count expected-answer)
    (let ((table (gethash "value" (parse source))))
      (expect (and (= expected-count (hash-table-count table))
                   (or (null expected-answer)
                       (toml-test-value= expected-answer
                                         (gethash "answer" table)))))))
  (it "accepts CRLF between document lines"
    (let ((table (parse (format nil "a = 1~C~Cb = 2~C~C"
                                #\Return #\Newline #\Return #\Newline))))
      (expect (and (toml-test-value= 1 (gethash "a" table))
                   (toml-test-value= 2 (gethash "b" table))))))
  (it "reads dotted keys and nested table values"
    (let ((table (parse (format nil
                               "fruit.name = \"apple\"~%[fruit.physical]~%color = \"red\"~%"))))
      (expect (toml-test-value=
               "apple" (gethash "name" (gethash "fruit" table))))
      (expect (toml-test-value=
               "red" (gethash "color"
                              (gethash "physical" (gethash "fruit" table)))))))
  (it "reads tables, array tables, and inline tables"
    (let ((table (parse
                  (with-output-to-string (stream)
                    (format stream "[owner]~%name = \"Tom\"~%")
                    (format stream "[[products]]~%name = \"A\"~%")
                    (format stream "[[products]]~%name = \"B\"~%")
                    (format stream "config = { enabled = true, count = 2 }~%")))))
      (expect (toml-test-value= "Tom" (gethash "name" (gethash "owner" table))))
      (expect (= 2 (length (gethash "products" table))))
      (expect (eql t (gethash "enabled"
                              (gethash "config"
                                       (aref (gethash "products" table) 1))))))))

(describe "TOML reader data macros"
  (it-each ((cl-toml-kit::define-char-class cl-toml-kit::+toml-bare-key-table+ #\a)
            (cl-toml-kit::define-toml-character-class (#\a #\b) #\a))
      "defines a hygienic character predicate"
      (macro entries character)
    (let* ((name (gensym "CHARACTER-PREDICATE-"))
           (definition (%macroexpanded-defun
                        (macroexpand-1 (list macro name entries)) name))
           (argument (first (third definition)))
           (evaluations 0))
      (expect (and (symbolp argument) (null (symbol-package argument))))
      (eval definition)
      (expect (funcall name (progn (incf evaluations) character)))
      (expect (= evaluations 1))))
  (it "generates an integer-range predicate with one argument evaluation"
    (let* ((macro-name (find-symbol "DEFINE-TOML-INTEGER-RANGE" "CL-TOML-KIT"))
           (minimum-name (find-symbol "+TOML-MIN-INTEGER+" "CL-TOML-KIT"))
           (maximum-name (find-symbol "+TOML-MAX-INTEGER+" "CL-TOML-KIT"))
           (predicate-name (find-symbol "%TOML-INTEGER-IN-RANGE-P" "CL-TOML-KIT"))
           (expansion
             (macroexpand-1
              (list macro-name
                    minimum-name -9223372036854775808
                    maximum-name 9223372036854775807
                    predicate-name)))
           (definition (%macroexpanded-defun expansion predicate-name))
           (argument (first (third definition)))
           (evaluations 0))
      (expect (and (symbolp argument) (null (symbol-package argument))))
      (eval definition)
      (expect (funcall predicate-name (progn (incf evaluations) 0)))
      (expect (= evaluations 1))))
  (it "maps lookup entries and signals on an unknown key"
    (let ((name (gensym "TOML-LOOKUP-")))
      (eval `(cl-toml-kit::define-toml-error-messages
              ,name
              ((:defined-table "defined table")
               (:array-table "array table"))
              :otherwise (error "Unknown lookup key")))
      (expect (string= "defined table" (funcall name :defined-table)))
      (expect (string= "array table" (funcall name :array-table)))
      (expect (signals error (funcall name :missing)))))
  (it "defines escape data and hexadecimal widths"
    (expect (string=
             (coerce '(#\b #\t #\n #\f #\r #\e #\" #\\) 'string)
             cl-toml-kit::+toml-escape-letters+))
    (expect (toml-test-value=
             (vector #\Backspace #\Tab #\Newline #\Page #\Return #\Escape #\" #\\)
             cl-toml-kit::+toml-escape-table+))
    (expect (toml-test-value=
             '(2 4 8 nil)
             (mapcar #'cl-toml-kit::%toml-hex-escape-width
                     '(#\x #\u #\U #\a))))))
