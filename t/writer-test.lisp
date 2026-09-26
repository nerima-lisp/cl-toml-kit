(in-package #:cl-toml-kit/test)

(defun %writer-table (&rest pairs)
  (let ((table (make-hash-table :test 'equal)))
    (loop for (key value) on pairs by #'cddr
          do (setf (gethash key table) value))
    table))

(describe "TOML writer"
  (it "writes scalar values and strings"
    (expect (string= (format nil "message = ~S~%flag = false~%number = 42~%"
                             "hello")
                     (encode (%writer-table "message" "hello"
                                             "flag" +toml-false+
                                             "number" 42)))))
  (it "escapes basic strings"
    (expect (string= (format nil "value = \"a\\nb\"~%")
                     (encode (%writer-table "value" (format nil "a~%b"))))))
  (it "writes arrays and inline tables"
    (let ((nested (%writer-table "x" 1)))
      (expect (string= (format nil "items = [1, 2]~%[nested]~%x = 1~%")
                       (encode (%writer-table "items" (vector 1 2)
                                               "nested" nested))))))
  (it "writes child tables after scalar values"
    (let ((child (%writer-table "value" "ok")))
      (expect (string= (format nil "root = true~%[child]~%value = ~S~%"
                               "ok")
                       (encode (%writer-table "child" child "root" t))))))
  (it "writes arrays of tables with repeated headers"
    (let ((first (%writer-table "name" "a"))
          (second (%writer-table "name" "b")))
      (expect (string= (format nil "[[items]]~%name = ~S~%[[items]]~%name = ~S~%"
                               "a" "b")
                       (encode (%writer-table "items" (vector first second)))))))
  (it "writes dates with cl-date-kit formatters"
    (let ((date (cl-date-kit:local-date-of 2026 1 2)))
      (expect (string= (format nil "date = 2026-01-02~%")
                       (encode (%writer-table "date" date))))))
  (it "writes TOML float spellings"
    (expect (string= (format nil "a = 1.0e0~%b = 1.5e0~%c = 1.0e20~%")
                     (encode (%writer-table "a" 1.0d0
                                             "b" 1.5d0
                                             "c" 1.0d20)))))
  (it "signals encoding errors with paths"
    (let ((condition (handler-case
                         (encode (%writer-table "outer"
                                                (%writer-table "inner" nil)))
                       (toml-encoding-error (error) error))))
      (expect (equal '("outer" "inner")
                     (toml-encoding-error-path condition))))
    (let ((condition (handler-case (encode nil)
                       (toml-encoding-error (error) error))))
      (expect (null (toml-encoding-error-path condition))))
    (let ((table (make-hash-table :test 'eq)))
      (setf (gethash "key" table) 1)
      (expect (signals toml-encoding-error (encode table))))
    (let ((table (make-hash-table :test 'equal)))
      (setf (gethash :key table) 1)
      (expect (signals toml-encoding-error (encode table)))))
  (it "writes directly to a supplied stream"
    (let ((stream (make-string-output-stream))
          (table (%writer-table "x" 1)))
      (expect (eq table (write-toml table stream)))
      (expect (string= (format nil "x = 1~%") (get-output-stream-string stream))))))
