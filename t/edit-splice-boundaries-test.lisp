(in-package #:cl-toml-kit/test)

(describe "editor regression boundaries"
  (it "edits inline-table fields and keeps the modified value"
    (let* ((source
             (%edit-test-bytes
              "settings = { first = 1, middle = 2, last = 3 }~%"))
           (edited (edit-toml source (list "settings" "middle") 4)))
      (expect (string= (%toml-test-format-text
                        "settings = { first = 1, middle = 4, last = 3 }~%")
                       (%edit-test-text edited)))
      (expect (= 4 (%edit-test-value edited (list "settings" "middle"))))))
  (it "deletes inline-table fields while retaining separators"
    (let* ((source
             (%edit-test-bytes
              "settings = { first = 1, middle = 2, last = 3 }~%"))
           (without-first (delete-toml source (list "settings" "first")))
           (without-last (delete-toml source (list "settings" "last"))))
      (expect (string= (%toml-test-format-text
                        "settings = { middle = 2, last = 3 }~%")
                       (%edit-test-text without-first)))
      (expect (string= (%toml-test-format-text
                        "settings = { first = 1, middle = 2 }~%")
                       (%edit-test-text without-last)))))
  (it "splices values after multibyte UTF-8 text at the right byte offset"
    (let* ((source (%edit-test-bytes "label = \"猫🙂\"~%count = 1~%"))
           (result (edit-toml source (list "count") 2)))
      (expect (string= (%toml-test-format-text
                        "label = \"猫🙂\"~%count = 2~%")
                       (%edit-test-text result)))
      (expect (= 2 (%edit-test-value result (list "count"))))))
  (it "adds the first item to an empty array"
    (let* ((array-source (%edit-test-bytes "values = []~%"))
           (array-result (edit-toml array-source (list "values" 0) 1)))
      (expect (string= (%toml-test-format-text "values = [1]~%")
                       (%edit-test-text array-result)))
      (expect (= 1 (%edit-test-value array-result (list "values" 0))))))
  (it "adds the first entry to an empty inline table"
    (let* ((inline-source (%edit-test-bytes "settings = {}~%"))
           (inline-result (edit-toml inline-source (list "settings" "mode") 1)))
      (expect (string= (%toml-test-format-text "settings = {mode = 1}~%")
                       (%edit-test-text inline-result)))
      (expect (= 1 (%edit-test-value inline-result (list "settings" "mode"))))))
  (it "deletes the only inline entry and the final array item"
    (let* ((inline-source (%edit-test-bytes "settings = {only = 1}~%"))
           (inline-result (delete-toml inline-source (list "settings" "only")))
           (array-source (%edit-test-bytes "values = [1, 2, 3]~%"))
           (array-result (delete-toml array-source (list "values" 2))))
      (expect (string= (%toml-test-format-text "settings = {}~%")
                       (%edit-test-text inline-result)))
      (expect (string= (%toml-test-format-text "values = [1, 2]~%")
                       (%edit-test-text array-result)))
      (expect (equalp #(1 2) (%edit-test-value array-result (list "values"))))))
  (it "appends to a nonempty array while preserving its trailing comma"
    (let* ((source (%edit-test-bytes "values = [1, 2,]~%"))
           (result (edit-toml source (list "values" 2) 3)))
      (expect
       (string= (%toml-test-format-text "values = [1, 2, 3,]~%")
                (%edit-test-text result)))
      (expect (equalp #(1 2 3) (%edit-test-value result (list "values")))))))

(describe "editor assignment and path-prefix boundaries"
  (it "deletes the final root assignment while retaining earlier lines"
    (let* ((source (%edit-test-bytes "first = 1~%second = 2~%third = 3~%"))
           (result (delete-toml source '("third"))))
      (expect (string= (%toml-test-format-text "first = 1~%second = 2~%")
                       (%edit-test-text result)))
      (expect (= 1 (%edit-test-value result '("first"))))
      (expect (= 2 (%edit-test-value result '("second"))))))
  (it "checks path prefixes by component and path length"
    (let ((prefix-p
            (symbol-function (find-symbol "%EDIT-PATH-PREFIX-P" "CL-TOML-KIT"))))
      (expect (funcall prefix-p '("a") '("a" "b")))
      (expect (not (funcall prefix-p '("a" "b") '("a"))))
      (expect (not (funcall prefix-p '("a" "x") '("a" "b")))))))

(describe "editor multiline array insertion boundaries"
  (it "appends at index one while preserving the multiline form"
    (let* ((source (%edit-test-bytes "values = [1,~%]~%"))
           (result (edit-toml source '("values" 1) 2)))
      (expect (string= (%toml-test-format-text "values = [1,~%2,~%]~%")
                       (%edit-test-text result)))
      (expect (equalp #(1 2)
                      (%edit-test-value result '("values")))))))
(describe "editor splice boundary outcomes"
  (it "deletes a sole array item without a trailing comma"
    (let* ((source (%edit-test-bytes "values = [1]~%"))
           (result (delete-toml source (list "values" 0))))
      (expect (string= (%toml-test-format-text "values = []~%")
                       (%edit-test-text result)))
      (expect (equalp #() (%edit-test-value result (list "values"))))))
  (it "uses the defaults for a newly constructed edit node"
    (let ((node
            (cl-toml-kit::%make-edit-node
             :path-reversed nil :start 0 :end 2)))
      (expect (= 0 (cl-toml-kit::edit-node-parent-depth node)))
      (expect (eq :value (cl-toml-kit::edit-node-kind node)))))
  (it "rejects edit nodes with invalid declared slot values"
    (let* ((constructor
             (symbol-function
              (find-symbol "%MAKE-EDIT-NODE" "CL-TOML-KIT")))
           (depth -1)
           (kind :invalid)
           (depth-error
             (handler-case
                 (progn
                   (funcall constructor
                            :path-reversed nil :start 0 :end 2 :parent-depth depth)
                   nil)
               (type-error (condition) condition)))
           (kind-error
             (handler-case
                 (progn
                   (funcall constructor
                            :path-reversed nil :start 0 :end 2 :kind kind)
                   nil)
               (type-error (condition) condition))))
      (expect (typep depth-error 'type-error))
      (expect (= depth (type-error-datum depth-error)))
      (expect (and (not (typep depth (type-error-expected-type depth-error)))
                   (typep 0 (type-error-expected-type depth-error))))
      (expect (typep kind-error 'type-error))
      (expect (eq kind (type-error-datum kind-error)))
      (expect (and (not (typep kind (type-error-expected-type kind-error)))
                   (typep :value (type-error-expected-type kind-error)))))))
