;;;; t/model-test.lisp
(in-package #:cl-toml-kit/test)

(describe "TOML value model"
  (it "keeps false distinct from absence"
    (let ((value (make-boolean-value nil)))
      (expect (boolean-value-p value))
      (expect (not (null (toml-value-p value))))
      (expect (eq :boolean (toml-value-kind value)))))
  (it "preserves table insertion order and empty collections"
    (let ((table (make-table-value))
          (array (make-array-value)))
      (toml-table-set table "first" (make-integer-value 1))
      (toml-table-set table "second" (make-string-value "two"))
      (expect (null (array-elements array)))
      (expect (equal '("first" "second")
                     (mapcar #'car (table-entries table))))
      (expect (= 1 (integer-value (table-value table "first")))))))
