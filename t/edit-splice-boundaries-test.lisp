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
