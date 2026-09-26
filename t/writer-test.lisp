(in-package #:cl-toml-kit/test)

(defun %writer-table (&rest pairs)
  (let ((table (make-hash-table :test 'equal)))
    (loop for (key value) on pairs by #'cddr
          do (setf (gethash key table) value))
    table))

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
  (it "writes all four cl-date-kit value kinds"
    (let ((offset (cl-date-kit:offset-date-time-of 2026 1 2 3 4 5))
          (date-time (cl-date-kit:local-date-time-of 2026 1 2 3 4 5))
          (date (cl-date-kit:local-date-of 2026 1 2))
          (time (cl-date-kit:local-time-of 3 4 5)))
      (expect (string= (format nil "offset = 2026-01-02T03:04:05Z~%")
                       (encode (%writer-table "offset" offset))))
      (expect (string= (format nil "date-time = 2026-01-02T03:04:05~%")
                       (encode (%writer-table "date-time" date-time))))
      (expect (string= (format nil "date = 2026-01-02~%")
                       (encode (%writer-table "date" date))))
      (expect (string= (format nil "time = 03:04:05~%")
                       (encode (%writer-table "time" time)))))
  (it "writes infinities, NaN, and the smallest subnormal"
    (let ((nan (sb-int:with-float-traps-masked (:invalid)
                 (/ 0.0d0 0.0d0))))
      (expect (string= (format nil "a = inf~%b = -inf~%c = nan~%d = 4.9406564584124654e-324~%")
                       (encode (%writer-table
                                "a" sb-ext:double-float-positive-infinity
                                "b" sb-ext:double-float-negative-infinity
                                "c" nan "d" least-positive-double-float)))))))
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
    (expect (string= (format nil expected) (encode (%writer-table key 1)))))
  )

(describe "TOML writer containers and paths"
  (it "writes empty tables as empty inline tables"
    (expect (string= (format nil "empty = {}~%")
                     (encode (%writer-table "empty"
                                             (make-hash-table :test 'equal))))))
  (it "writes values before tables and preserves nested header paths"
    (let ((child (%writer-table "value" 1))
          (grandchild (%writer-table "leaf" 2)))
      (setf (gethash "grand" child) grandchild)
      (expect (string= (format nil "root = true~%[child]~%value = 1~%[child.grand]~%leaf = 2~%")
                       (encode (%writer-table "child" child "root" t))))))
  (it "writes arrays and nested arrays of tables"
    (let ((first (%writer-table "name" "a"))
          (second (%writer-table "name" "b")))
      (expect (string= (format nil "[[items]]~%name = \"a\"~%[[items]]~%name = \"b\"~%")
                       (encode (%writer-table "items" (vector first second)))))))
  (it-property "encoding is deterministic for random value trees"
      ((value (gen-recursive
               (gen-one-of (gen-integer :min -10 :max 10)
                           (gen-string :max-length 8)
                           (gen-member (list t +toml-false+)))
               (lambda (child)
                 (gen-map (lambda (item)
                            (%writer-table "child" item))
                          child)))))
    (let ((table (%writer-table "value" value)))
      (expect (string= (encode table) (encode table))))))

(describe "TOML writer errors"
  (it-each ((nil nil)
            ((quote (1 2)) nil)
            (:symbol nil)
            (9223372036854775808 nil))
      "rejects unsupported value ~S with a path"
      (value ignored)
    (declare (ignore ignored))
    (let ((condition (handler-case
                         (encode (%writer-table "outer"
                                                (%writer-table "inner" value)))
                       (toml-encoding-error (error) error))))
      (expect (typep condition 'toml-encoding-error))
      (expect (equal '("outer" "inner")
                     (toml-encoding-error-path condition)))
      (expect (search "value" (toml-encoding-error-message condition)))))
  (it "rejects non-EQUAL tables and non-string keys"
    (let ((eq-table (make-hash-table :test 'eq))
          (bad-key-table (make-hash-table :test 'equal)))
      (setf (gethash "key" eq-table) 1
            (gethash :key bad-key-table) 1)
      (expect (signals toml-encoding-error (encode eq-table)))
      (expect (signals toml-encoding-error (encode bad-key-table))))))
