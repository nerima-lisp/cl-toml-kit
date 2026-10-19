(in-package #:cl-toml-kit/test)

(defun %roundtrip-generated-values (self)
  (toml-test-value-generator
   self
   :integer-min -100000
   :integer-max 100000
   :strings (list "" "text" "日本語" (format nil "line~%text"))
   :additional-scalars (list 0.1d0 1.0d308 least-positive-double-float)
   :array-max-length 3))

(defun %register-roundtrip-tests ()
  (let ((fixtures (getf (load-toml-fixtures) :valid)))
    ;; it-each requires literal cases at macro expansion, so runtime fixtures use EVAL.
    (eval `(it-each
             ,(mapcar (lambda (fixture)
                        (list (namestring (toml-fixture-toml fixture)))) fixtures)
             "round-trips valid TOML fixture ~A"
             (name)
             (let* ((first (parse-file (pathname name)))
                    (second (parse (encode first))))
               (expect (toml-test-value= first second)))))))

(it-property "preserves generated TOML values through encoding and parsing"
    ((table (toml-test-document-generator
            (gen-recursive
             (gen-one-of (gen-integer :min -1000 :max 1000)
                         (gen-member (list "text" "日本語" t +toml-false+ 1.5d0)))
             #'%roundtrip-generated-values
             :max-depth 4))))
  (expect (toml-test-value= table (parse (encode table)))))
