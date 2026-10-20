(in-package #:cl-toml-kit/test)

(describe "editor regression boundaries"
  (it "counts array-table headers through internal %edit-toml callbacks"
    (let* ((groups 128)
           (header-count (* 2 groups))
           (prefix-bound (* 8 header-count))
           (source
             (%edit-test-bytes
              (with-output-to-string (stream)
                (dotimes (index groups)
                  (format stream
                          "[[nested-~D.child]]~%value = ~D~%[[item-~D]]~%value = ~D~%"
                          index index index index)))))
           (counter-calls 0)
           (prefix-calls 0)
           (target-index (1- groups))
           (target-key (format nil "item-~D" target-index))
           (result
             (cl-toml-kit::%edit-toml source
              (list target-key 0 "value")
              -1 t nil
              :array-table-counter-path
              (lambda (header latest)
                (incf counter-calls)
                (cl-toml-kit::%edit-array-table-counter-path header latest))
              :path-prefix-p
              (lambda (prefix path)
                (incf prefix-calls)
                (cl-toml-kit::%edit-path-prefix-p prefix path)))))
      (expect (= header-count counter-calls))
      (expect (<= prefix-calls prefix-bound))
      (expect (= -1 (%edit-test-value result (list target-key 0 "value"))))))
  (it "preserves nested array-table values through edit-toml"
    (let* ((groups 128)
           (source
             (%edit-test-bytes
              (with-output-to-string (stream)
                (dotimes (index groups)
                  (format stream
                          "[[nested-~D.child]]~%value = ~D~%[[item-~D]]~%value = ~D~%"
                          index index index index)))))
           (target-index (1- groups))
           (target-key (format nil "item-~D" target-index))
           (result (edit-toml source (list target-key 0 "value") -1)))
      (let ((parsed (%edit-test-parse result)))
        (dotimes (index groups)
          (let* ((nested-key (format nil "nested-~D" index))
                 (nested-table (gethash nested-key parsed))
                 (children (gethash "child" nested-table)))
            (expect (= 1 (length children)))
            (expect (= index (gethash "value" (aref children 0)))))))))
  (it "preserves array-table item values through edit-toml"
    (let* ((groups 128)
           (source
             (%edit-test-bytes
              (with-output-to-string (stream)
                (dotimes (index groups)
                  (format stream
                          "[[nested-~D.child]]~%value = ~D~%[[item-~D]]~%value = ~D~%"
                          index index index index)))))
           (target-index (1- groups))
           (target-key (format nil "item-~D" target-index))
           (result (edit-toml source (list target-key 0 "value") -1)))
      (let ((parsed (%edit-test-parse result)))
        (dotimes (index groups)
          (let* ((item-key (format nil "item-~D" index))
                 (items (gethash item-key parsed))
                 (item-value (if (= index target-index) -1 index)))
            (expect (= 1 (length items)))
            (expect (= item-value (gethash "value" (aref items 0)))))))))
  (it "scans escaped keys and counts two-byte UTF-8 offsets"
    (let* ((source (%edit-test-bytes "\"é\" = 1~%\"line\\nkey\" = 2~%"))
           (first-result (edit-toml source (list "é") 3))
           (key (format nil "line~%key"))
           (result (edit-toml first-result (list key) 4)))
      (expect (string= (%toml-test-format-text "\"é\" = 3~%\"line\\nkey\" = 4~%")
                       (%edit-test-text result)))
      (expect (= 3 (%edit-test-value result (list "é"))))
      (expect (= 4 (%edit-test-value result (list key))))))
  (it "preserves Unicode quoted-key escapes and values"
    (let* ((source
             (%edit-test-bytes
              (concatenate
               'string
               "\"quote\\\"key\" = 1~%\"small\\u00e9\" = 2~%"
               "\"face\\U0001F642\" = 3~%'literal' = 4~%")))
           (quoted (edit-toml source (list "quote\"key") 5))
           (small (edit-toml quoted (list "smallé") 6))
           (face (edit-toml small (list "face🙂") 7))
           (result (edit-toml face (list "literal") 8)))
      (expect (string=
               (%toml-test-format-text
                (concatenate 'string
                             "\"quote\\\"key\" = 5~%\"small\\u00e9\" = 6~%"
                             "\"face\\U0001F642\" = 7~%'literal' = 8~%"))
               (%edit-test-text result)))
      (expect (= 5 (%edit-test-value result (list "quote\"key"))))
      (expect (= 6 (%edit-test-value result (list "smallé"))))))
  (it "checks supplementary Unicode and literal quoted keys"
    (let* ((source
             (%edit-test-bytes
              (concatenate
               'string
               "\"quote\\\"key\" = 1~%\"small\\u00e9\" = 2~%"
               "\"face\\U0001F642\" = 3~%'literal' = 4~%")))
           (quoted (edit-toml source (list "quote\"key") 5))
           (small (edit-toml quoted (list "smallé") 6))
           (face (edit-toml small (list "face🙂") 7))
           (result (edit-toml face (list "literal") 8)))
      (expect (= 7 (%edit-test-value result (list "face🙂"))))
      (expect (= 8 (%edit-test-value result (list "literal"))))))
  (it "checks character, key, and basic string scanner bounds"
    (let* ((char-at-limit
              (symbol-function (find-symbol "%EDIT-CHAR" "CL-TOML-KIT")))
           (key-component
             (symbol-function
              (find-symbol "%EDIT-SCAN-KEY-COMPONENT" "CL-TOML-KIT")))
           (scan-string
             (symbol-function (find-symbol "%EDIT-SCAN-STRING" "CL-TOML-KIT"))))
      (expect (null (funcall char-at-limit "x" 1 1)))
      (expect
       (equal (multiple-value-list (funcall key-component "bare" 0 4))
              (list "bare" 4)))
      (expect (= 3 (funcall scan-string "\"x\"" 0 3)))))
  (it "checks triple-string scanning and comment trivia"
    (let* ((scan-string
             (symbol-function (find-symbol "%EDIT-SCAN-STRING" "CL-TOML-KIT")))
           (skip-trivia
             (symbol-function
              (find-symbol "%EDIT-SKIP-COMMENT-AND-TRIVIA" "CL-TOML-KIT")))
           (comment (format nil "# comment~%  value")))
      (expect (= 7 (funcall scan-string "\"\"\"x\"\"\"" 0 7)))
      (expect (signals error (funcall scan-string "\"open" 0 5)))
      (expect
       (= (position #\v comment)
          (funcall skip-trivia comment 0 (length comment))))))
  (it "rejects invalid key and container scanners"
    (let* ((key-component
             (symbol-function
              (find-symbol "%EDIT-SCAN-KEY-COMPONENT" "CL-TOML-KIT")))
           (scan-array
             (symbol-function (find-symbol "%EDIT-SCAN-ARRAY-NODE" "CL-TOML-KIT")))
           (scan-inline
             (symbol-function (find-symbol "%EDIT-SCAN-INLINE-NODE" "CL-TOML-KIT"))))
      (expect (signals error (funcall key-component "?" 0 1)))
      (expect (signals error
                (funcall scan-array "[1" 0 2 nil nil 1 4
                         "TOML nesting depth limit exceeded")))
      (expect (signals error
                (funcall scan-inline "{a=1" 0 4 nil nil 1 4
                         "TOML nesting depth limit exceeded")))))
  (it "uses adjacent CRLF and LF boundaries"
    (let* ((line-ending
             (symbol-function (find-symbol "%EDIT-LINE-ENDING" "CL-TOML-KIT")))
           (crlf (format nil "a~C~Cb" #\Return #\Newline)))
      (expect
       (string= (format nil "~C~C" #\Return #\Newline)
                (funcall line-ending crlf 3)))
      (expect
       (string= (string #\Newline)
                (funcall line-ending (format nil "a~%b") 2)))))
  (it "uses end-of-document line-ending fallback"
    (let* ((line-ending
             (symbol-function (find-symbol "%EDIT-LINE-ENDING" "CL-TOML-KIT")))
           (next-crlf (format nil "a~C~C" #\Return #\Newline)))
      (expect
       (string= (format nil "~C~C" #\Return #\Newline)
                (funcall line-ending next-crlf 0)))
      (expect
       (string= (string #\Newline)
                (funcall line-ending "abc" 0)))))
  (it "shares a parent's reversed path with its child"
    (let* ((assignments
             (first
              (multiple-value-list
               (cl-toml-kit::%edit-scan-document "value = [1]"))))
           (parent (cl-toml-kit::edit-assignment-node (first assignments)))
           (child (first (cl-toml-kit::edit-node-children parent))))
      (expect
       (eq (cdr (cl-toml-kit::edit-node-path-reversed child))
           (cl-toml-kit::edit-node-path-reversed parent))))))
