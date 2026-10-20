(in-package #:cl-toml-kit/test)

(describe "editor regression boundaries"
  (it "rejects a non-octet vector without changing it"
    (let* ((source (vector 110 97 256 101))
           (snapshot (copy-seq source)))
      (expect (signals type-error
                (edit-toml source (list "name") "new")))
      (expect (equalp snapshot source))))
  (it "accepts string and vector paths"
    (let* ((source (%edit-test-bytes "name = 1~%"))
           (string-path (edit-toml source "name" 2))
           (vector-path (edit-toml source (vector "name") 3)))
      (expect (= 2 (%edit-test-value string-path (list "name"))))
      (expect (= 3 (%edit-test-value vector-path (list "name"))))))
  (it "rejects invalid editor paths"
    (let* ((source (%edit-test-bytes "name = 1~%")))
      (expect (signals toml-format-preservation-error
                       (edit-toml source nil 4)))
      (expect (signals toml-format-preservation-error
                       (edit-toml source (list -1) 4)))
      (expect (signals toml-format-preservation-error
                       (edit-toml source (make-symbol "name") 4)))))
  (it "compares semantic table values"
    (let* ((equal-value
             (symbol-function (find-symbol "%EDIT-VALUE-EQUAL-P" "CL-TOML-KIT")))
           (left (make-hash-table :test (function equal)))
           (same (make-hash-table :test (function equal)))
           (empty (make-hash-table :test (function equal)))
           (other (make-hash-table :test (function equal))))
      (setf (gethash "left" left) 1
            (gethash "left" same) 1
            (gethash "right" other) 1)
      (expect (funcall equal-value left same))
      (expect (not (funcall equal-value left empty)))
      (expect (not (funcall equal-value left other)))))
  (it "compares scalar and vector values"
    (let* ((equal-value
             (symbol-function (find-symbol "%EDIT-VALUE-EQUAL-P" "CL-TOML-KIT")))
           (left (make-hash-table :test (function equal))))
      (expect (not (funcall equal-value left 1)))
      (expect (funcall equal-value #(1) #(1)))
      (expect (not (funcall equal-value #(1) #(2))))))
  (it "rejects unequal vectors and overlapping byte edits"
    (let* ((equal-value
             (symbol-function (find-symbol "%EDIT-VALUE-EQUAL-P" "CL-TOML-KIT")))
           (apply-bytes
             (symbol-function (find-symbol "%EDIT-APPLY-BYTES" "CL-TOML-KIT"))))
      (expect (not (funcall equal-value #(1 2) #(1))))
      (expect (not (funcall equal-value #() nil)))
      (expect (signals toml-format-preservation-error
                       (funcall apply-bytes #(1 2 3)
                                (list (list 0 2 #(9))
                                      (list 1 3 #(8))))))))
  (it "uses edit-toml for replacement and deletion"
    (let* ((source (%edit-test-bytes "name = 1~%"))
           (replaced (edit-toml source (list "name") 2))
           (deleted (edit-toml replaced (list "name") nil :delete t)))
      (expect (= 2 (%edit-test-value replaced (list "name"))))
      (expect (string= "" (%edit-test-text deleted)))
      (expect (= 0 (hash-table-count (%edit-test-parse deleted))))))
  (it "rejects ambiguous array-table additions without mutation"
    (let* ((source
              (%edit-test-bytes
               "[[products]]~%name = 1~%[[products]]~%name = 2~%"))
           (original (copy-seq source)))
      (expect
       (signals toml-format-preservation-error
         (edit-toml source (list "products" "extra") 3)))
      (expect (equalp original source))))
  (it "rejects absent deletes without mutation"
    (let* ((source
              (%edit-test-bytes
               "[[products]]~%name = 1~%[[products]]~%name = 2~%"))
           (original (copy-seq source)))
      (expect
       (signals toml-format-preservation-error
         (delete-toml source (list "missing"))))
      (expect (equalp original source))))
  (it "updates and appends semantic arrays"
    (let* ((change
             (symbol-function (find-symbol "%EDIT-SEMANTIC-CHANGE" "CL-TOML-KIT")))
           (table (make-hash-table :test (function equal)))
           (nested-result nil))
      (setf (gethash "value" table) 1
            nested-result
              (funcall change (vector table) (list 0 "value") 2 nil))
      (expect (= 2 (gethash "value" (aref nested-result 0))))
      (expect (equalp #(1 2) (funcall change (vector 1) (list 1) 2 nil)))
      (expect
       (equalp #(9 2) (funcall change (vector 1 2) (list 0) 9 nil)))))
  (it "deletes and rejects invalid semantic array updates"
    (let* ((change
             (symbol-function (find-symbol "%EDIT-SEMANTIC-CHANGE" "CL-TOML-KIT")))
           (table (make-hash-table :test (function equal))))
      (setf (gethash "value" table) 1)
      (expect
       (equalp #(2) (funcall change (vector 1 2) (list 0) nil t)))
      (expect (signals error (funcall change 1 (list "key") 2 nil)))
      (expect (signals error (funcall change table (list 0) 2 nil)))))
  (it "rejects missing and negative semantic paths"
    (let* ((change
             (symbol-function (find-symbol "%EDIT-SEMANTIC-CHANGE" "CL-TOML-KIT")))
           (table (make-hash-table :test (function equal))))
      (setf (gethash "value" table) 1)
      (expect (signals error (funcall change table (list "missing") nil t)))
      (expect (signals error (funcall change #(1) (list -1) 0 nil))))))
