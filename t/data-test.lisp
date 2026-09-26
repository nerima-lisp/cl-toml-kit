;;;; t/data-test.lisp
(in-package #:cl-toml-kit/test)

(describe "native TOML value model"
  (it-each (("text" :string)
            (42 :integer)
            (t :true))
      "classifies scalar ~S as ~S"
      (value expected)
    (expect (toml-value-p value))
    (expect (eq expected (toml-value-kind value))))
  (it-each (("text" string)
            (42 toml-integer)
            (1.0d0 toml-float)
            (t (eql t)))
      "matches generated type ~S"
      (value type)
    (expect (typep value type)))
  (it "classifies the false sentinel"
    (expect (eq :false (toml-value-kind +toml-false+))))
  (it "matches the generated false sentinel type"
    (expect (typep +toml-false+ (satisfies toml-false-p))))
  (it "classifies all native containers and date values"
    (let ((table (make-hash-table :test 'equal))
          (array (make-array 0 :element-type t))
          (offset-date-time (cl-date-kit:offset-date-time-of 2026 1 1 0 0 0))
          (local-date-time (cl-date-kit:local-date-time-of 2026 1 1 0 0 0))
          (local-date (cl-date-kit:local-date-of 2026 1 1))
          (local-time (cl-date-kit:local-time-of 0 0 0)))
      (dolist (case (list (list table :table)
                          (list array :array)
                          (list offset-date-time :offset-date-time)
                          (list local-date-time :local-date-time)
                          (list local-date :local-date)
                          (list local-time :local-time)))
        (destructuring-bind (value expected) case
          (expect (toml-value-p value))
          (expect (eq expected (toml-value-kind value)))))))
  (it-each ((-9223372036854775808 t)
            (9223372036854775807 t)
            (9223372036854775808 nil)
            (-9223372036854775809 nil))
      "checks integer boundary ~S"
      (value expected)
    (expect (eq expected (toml-value-p value))))
  (it "accepts double-float infinity and NaN"
    (expect (toml-value-p sb-ext:double-float-positive-infinity))
    (expect (toml-value-p sb-ext:double-float-negative-infinity))
    (let ((nan (sb-int:with-float-traps-masked (:invalid)
                 (/ 0.0d0 0.0d0))))
      (expect (toml-value-p nan))))
  (it "uses O(1) table identity and does not inspect keys"
    (let ((equal-table (make-hash-table :test 'equal))
          (eql-table (make-hash-table :test 'eql)))
      (setf (gethash 'not-a-string equal-table) 1)
      (expect (toml-table-p equal-table))
      (expect (toml-value-p equal-table))
      (expect (not (toml-table-p eql-table)))))
  (it "keeps false sentinel identity across source reload"
    (let ((sentinel +toml-false+))
      (load (asdf:system-relative-pathname "cl-toml-kit" "src/data.lisp"))
      (expect (eq sentinel +toml-false+))))
  (it "dispatches directly by type"
    (expect (eq :string
                (toml-value-typecase "value"
                  (:string :string)
                  (t :other))))
    (expect (eq :fallback
                (toml-value-typecase nil
                  (t :fallback)))))
  (it "rejects an unknown typecase kind during macro expansion"
    (expect (signals error
              (macroexpand-1 '(toml-value-typecase value (:unknown t)))))))

(describe "unsupported native values"
  (it-each ((nil) ((quote (1 2))) (:symbol))
      "rejects ~S"
      (value)
    (expect (not (toml-value-p value)))))
