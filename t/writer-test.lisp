(in-package #:cl-toml-kit/test)

(defun %writer-table (&rest pairs)
  (let ((table (make-hash-table :test 'equal)))
    (loop for (key value) on pairs by #'cddr
          do (setf (gethash key table) value))
    table))

(defun %writer-nan ()
  (sb-int:with-float-traps-masked (:invalid)
    (/ 0.0d0 0.0d0)))

(defun %writer-float-value (text)
  (cond ((string= text "inf") sb-ext:double-float-positive-infinity)
        ((string= text "-inf") sb-ext:double-float-negative-infinity)
        ((string= text "nan") (%writer-nan))
        (t (let ((*read-eval* nil)
                 (*read-default-float-format* 'double-float))
             (read-from-string text)))))

(defun %writer-float-text (encoded)
  (subseq encoded (length "value = ") (1- (length encoded))))

(defun %writer-float= (expected actual)
  (if (sb-ext:float-nan-p expected)
      (sb-ext:float-nan-p actual)
      (= expected actual)))

(defun %writer-valid-line-p (line)
  (or (and (> (length line) 2)
           (char= #\[ (char line 0))
           (if (char= #\[ (char line 1))
               (and (char= #\] (char line (- (length line) 1)))
                    (char= #\] (char line (- (length line) 2))))
               (char= #\] (char line (- (length line) 1)))))
      (let ((separator (search " = " line)))
        (and separator (plusp separator)
             (< (+ separator 3) (length line))))))

(defun %writer-valid-toml-lines-p (text)
  (with-input-from-string (stream text)
    (loop for line = (read-line stream nil)
          while line
          always (%writer-valid-line-p line))))

(defun %writer-date-values ()
  (list (cl-date-kit:offset-date-time-of 2026 1 2 3 4 5)
        (cl-date-kit:local-date-time-of 2026 1 2 3 4 5)
        (cl-date-kit:local-date-of 2026 1 2)
        (cl-date-kit:local-time-of 3 4 5)))

(defun %writer-generated-values (self)
  (gen-one-of
   (gen-one-of (gen-integer :min -1000 :max 1000)
               (gen-string :max-length 8)
               (gen-member (list t +toml-false+ 1.5d0 -0.0d0
                                  sb-ext:double-float-positive-infinity
                                  sb-ext:double-float-negative-infinity
                                  (%writer-nan)))
   (gen-member (%writer-date-values)))
   (gen-map (lambda (item) (%writer-table "child" item)) self)
   (cl-weave:gen-vector self :min-length 0 :max-length 3)))

(describe "TOML writer scalar data"
  (it-each (("hello" "message = \"hello\"~%")
            (42 "message = 42~%")
            (1.5d0 "message = 1.5~%")
            (1.0d0 "message = 1.0~%")
            (1.0d20 "message = 1.0e20~%")
            (-0.0d0 "message = -0.0~%")
            (t "message = true~%"))
      "writes ~S as ~S"
      (value expected)
    (expect (string= (format nil expected)
                     (encode (%writer-table "message" value)))))
  (it "writes the false sentinel"
    (expect (string= (format nil "message = false~%")
                     (encode (%writer-table "message" +toml-false+)))))
  (it-property "reads back every generated double-float"
      ((value (gen-member (list -0.0d0 0.0d0 1.5d0 1.0d20
                                  least-positive-double-float
                                  most-positive-double-float
                                  sb-ext:double-float-positive-infinity
                                  sb-ext:double-float-negative-infinity
                                  (%writer-nan)))))
    (let* ((encoded (encode (%writer-table "value" value)))
           (read-back (%writer-float-value (%writer-float-text encoded))))
      (expect (%writer-float= value read-back))))
  (it "writes all four cl-date-kit value kinds with RFC3339 formats"
    (destructuring-bind (offset date-time date time) (%writer-date-values)
    (expect (string= (format nil "offset = 2026-01-02T03:04:05Z~%")
                       (encode (%writer-table "offset" offset))))
      (expect (string= (format nil "date-time = 2026-01-02T03:04:05~%")
                       (encode (%writer-table "date-time" date-time))))
      (expect (string= (format nil "date = 2026-01-02~%")
                       (encode (%writer-table "date" date))))
      (expect (string= (format nil "time = 03:04:05~%")
                       (encode (%writer-table "time" time))))))
  (it "writes infinities, NaN, and the smallest subnormal"
    (expect (string= (format nil "a = inf~%b = -inf~%c = nan~%d = 4.9406564584124654e-324~%")
                     (encode (%writer-table
                              "a" sb-ext:double-float-positive-infinity
                              "b" sb-ext:double-float-negative-infinity
                              "c" (%writer-nan)
                              "d" least-positive-double-float)))))
  (it "escapes every basic-string control form including DEL"
    (expect (string= (format nil "value = \"\\b\\t\\n\\f\\r\\\"\\\\\\u0000\\u001F\\u007F\"~%")
                     (encode (%writer-table "value"
                                             (format nil "~C~C~C~C~C~C~C~C~C~C"
                                                     #\Backspace #\Tab #\Newline
                                                     #\Page #\Return #\" #\\
                                                     (code-char 0) (code-char 31)
                                                     (code-char 127)))))))
  (it-each (("plain-key" "plain-key = 1~%")
            ("has space" "\"has space\" = 1~%")
            ("" "\"\" = 1~%"))
      "writes key ~S using the correct key syntax"
      (key expected)
    (expect (string= (format nil expected) (encode (%writer-table key 1))))))

(describe "TOML writer containers and paths"
  (it "writes empty tables as empty inline tables"
    (expect (string= (format nil "empty = {}~%")
                     (encode (%writer-table "empty"
                                             (make-hash-table :test 'equal))))))
  (it "writes values before nested tables and preserves paths"
    (let ((child (%writer-table "value" 1))
          (grandchild (%writer-table "leaf" 2)))
      (setf (gethash "grand" child) grandchild)
      (expect (string= (format nil "root = true~%[child]~%value = 1~%[child.grand]~%leaf = 2~%")
                       (encode (%writer-table "child" child "root" t))))))
  (it "writes arrays of tables"
    (let ((first (%writer-table "name" "a"))
          (second (%writer-table "name" "b")))
      (expect (string= (format nil "[[items]]~%name = \"a\"~%[[items]]~%name = \"b\"~%")
                       (encode (%writer-table "items" (vector first second)))))))
  (it-property "generated arrays and nested tables are deterministic and line-valid"
      ((value (gen-recursive
               (gen-one-of (gen-integer :min -10 :max 10)
                           (gen-string :max-length 8)
                           (gen-member (list t +toml-false+)))
               #'%writer-generated-values
               :max-depth 3)))
    (let* ((table (%writer-table "value" value))
           (first (encode table))
           (second (encode table)))
      (expect (string= first second))
      (expect (%writer-valid-toml-lines-p first)))))

(describe "TOML writer errors"
  (it-each ((:nil "Unsupported TOML value" ("outer" "inner"))
            (:list "Unsupported TOML value" ("outer" "inner"))
            (:symbol "Unsupported TOML value" ("outer" "inner"))
            (:large-integer "Integer is outside TOML's signed 64-bit range"
                            ("outer" "inner"))
            (:eql-table "Table must use the EQUAL hash-table test" nil)
            (:non-string-key "Table keys must be strings" ("BAD")))
      "signals a bounded encoding error for ~S"
      (kind expected-message expected-path)
    (let ((condition
            (handler-case
                (encode
                 (case kind
                   (:eql-table (let ((table (make-hash-table :test 'eql)))
                                (setf (gethash "key" table) 1)
                                table))
                   (:non-string-key (let ((table (make-hash-table :test 'equal)))
                                      (setf (gethash :bad table) 1)
                                      table))
                   (otherwise
                    (%writer-table
                     "outer"
                     (%writer-table
                      "inner"
                      (ecase kind
                        (:nil nil)
                        (:list '(1 2))
                        (:symbol :symbol)
                        (:large-integer 9223372036854775808)))))))
              (toml-encoding-error (error) error))))
      (expect (typep condition 'toml-encoding-error))
      (expect (search expected-message
                      (toml-encoding-error-message condition)))
      (expect (equal expected-path (toml-encoding-error-path condition))))))
