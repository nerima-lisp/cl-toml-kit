;;;; t/model-test.lisp
(in-package #:cl-toml-kit/test)

(describe "native TOML value model"
  (it "uses native scalar values"
    (expect (toml-value-p "text"))
    (expect (toml-value-p 42))
    (expect (toml-value-p 1.0d0))
    (expect (toml-value-p t))
    (expect (toml-false-p +toml-false+))
    (expect (not (toml-value-p nil))))
  (it "uses equal hash tables and simple vectors for containers"
    (let ((table (make-hash-table :test 'equal))
          (array (make-array 2 :element-type t)))
      (setf (gethash "key" table) 42)
      (expect (toml-table-p table))
      (expect (toml-array-p array))
      (expect (eq :table (toml-value-kind table)))
      (expect (eq :array (toml-value-kind array)))))
  (it "rejects unsupported container representations"
    (expect (not (toml-value-p nil)))
    (expect (not (toml-value-p '(1 2))))))
