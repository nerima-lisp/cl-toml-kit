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

(describe "TOML definition macro expansions"
  (it "keeps define-char-class predicate arguments hygienic"
    (let* ((name (gensym "CHAR-CLASS-"))
           (expansion
             (macroexpand-1
              `(cl-toml-kit::define-char-class
                ,name cl-toml-kit::+toml-bare-key-table+)))
           (definition (%macroexpanded-defun expansion name))
           (argument (first (third definition)))
           (evaluations 0))
      (expect (and (symbolp argument) (null (symbol-package argument))))
      (eval definition)
      (expect (funcall name (progn (incf evaluations) #\a)))
      (expect (= evaluations 1))))
  (it "defines character classes with hygienic predicate arguments"
    (let* ((name (gensym "TOML-CHARACTER-CLASS-"))
           (expansion
             (macroexpand-1
              `(cl-toml-kit::define-toml-character-class
                ,name (#\a #\b))))
           (definition (%macroexpanded-defun expansion name))
           (argument (first (third definition)))
           (evaluations 0))
      (expect (and (symbolp argument) (null (symbol-package argument))))
      (eval definition)
      (expect (funcall name (progn (incf evaluations) #\a)))
      (expect (= evaluations 1))))
  (it "defines character maps with hygienic predicate arguments"
    (let* ((name (gensym "TOML-CHARACTER-MAP-"))
           (expansion
             (macroexpand-1
              `(cl-toml-kit::define-toml-character-map
                ,name ((#\x :two) (#\u :four) (#\U :eight)))))
           (definition (%macroexpanded-defun expansion name))
           (argument (first (third definition)))
           (evaluations 0))
      (expect (and (symbolp argument) (null (symbol-package argument))))
      (eval definition)
      (expect (eq :four (funcall name
                                 (progn (incf evaluations) #\u))))
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
      (progn
        (eval definition)
        (expect (funcall predicate-name (progn (incf evaluations) 0))))
      (expect (= evaluations 1))))
  (it "generates integer-radix lookups with one argument evaluation"
      (let* ((name (gensym "INTEGER-RADIXES-"))
             (macro-name (find-symbol "DEFINE-TOML-INTEGER-RADICES" "CL-TOML-KIT"))
             (expansion
              (macroexpand-1
               (list macro-name name
                     (list (list #\x 16) (list #\o 8) (list #\b 2)))))
             (definition (%macroexpanded-defun expansion name))
             (argument (first (third definition)))
             (evaluations 0))
        (expect (and (symbolp argument) (null (symbol-package argument))))
        (eval definition)
        (expect (= 16 (funcall name (progn (incf evaluations) #\x))))
        (expect (= evaluations 1))))
  (it "generates error-message lookups with one argument evaluation"
  (let* ((name (gensym "ERROR-MESSAGES-"))
         (macro-name (find-symbol "DEFINE-TOML-ERROR-MESSAGES" "CL-TOML-KIT"))
         (entries (list (list :defined-table "defined table")
                        (list :array-table "array table")))
         (expansion (macroexpand-1 (list macro-name name entries)))
         (definition (%macroexpanded-defun expansion name))
         (argument (first (third definition)))
         (evaluations 0))
    (expect (and (symbolp argument) (null (symbol-package argument))))
    (progn
      (eval definition)
      (expect
        (and (string= "defined table" (funcall name
                                   (progn (incf evaluations) :defined-table)))
             (string= "array table" (funcall name :array-table)))))
    (expect (= evaluations 1))))
  (it "keeps escape data and hex widths in the expansion"
  (let* ((macro-name (find-symbol "DEFINE-TOML-ESCAPE-DATA" "CL-TOML-KIT"))
         (character-map-name
           (find-symbol "DEFINE-TOML-CHARACTER-MAP" "CL-TOML-KIT"))
         (letters-name (find-symbol "+TOML-ESCAPE-LETTERS+" "CL-TOML-KIT"))
         (table-name (find-symbol "+TOML-ESCAPE-TABLE+" "CL-TOML-KIT"))
         (width-name (find-symbol "%TOML-HEX-ESCAPE-WIDTH" "CL-TOML-KIT"))
         (entries '((#\b #\Backspace) (#\t #\Tab)))
         (widths '((#\x 2) (#\u 4) (#\U 8)))
         (expansion (macroexpand-1 (list macro-name entries widths)))
         (forms (rest expansion))
         (letters-definition
           (find-if (lambda (form)
                      (and (consp form)
                           (eq (first form) 'defparameter)
                           (eq (second form) letters-name)))
                    forms))
         (table-definition
           (find-if (lambda (form)
                      (and (consp form)
                           (eq (first form) 'defparameter)
                           (eq (second form) table-name)))
                    forms))
         (width-map
           (find-if (lambda (form)
                      (and (consp form)
                           (eq (first form) character-map-name)
                           (eq (second form) width-name)))
                    forms)))
    (expect (and letters-definition table-definition))
    (expect (and width-map (equal (third width-map) widths))))))
