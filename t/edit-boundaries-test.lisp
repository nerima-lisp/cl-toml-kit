(in-package #:cl-toml-kit/test)

(describe "editor regression boundaries"
  (it "keeps mixed array-table scans linear in header count"
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
           (counter
             (find-symbol "%EDIT-ARRAY-TABLE-COUNTER-PATH" "CL-TOML-KIT"))
           (prefix-check
             (find-symbol "%EDIT-PATH-PREFIX-P" "CL-TOML-KIT"))
           (counter-calls
             (intern "*EDIT-PHASE2B-COUNTER-CALLS*" "CL-TOML-KIT/TEST"))
           (prefix-calls
             (intern "*EDIT-PHASE2B-PREFIX-CALLS*" "CL-TOML-KIT/TEST"))
           (original-counter (symbol-function counter))
           (original-prefix-check (symbol-function prefix-check))
           (target-index (1- groups))
           (target-key (format nil "item-~D" target-index))
           (result nil))
      (progv (list counter-calls prefix-calls) (list 0 0)
        (unwind-protect
            (progn
              (setf (symbol-function counter)
                    (lambda (header latest)
                      (when (boundp counter-calls)
                        (incf (symbol-value counter-calls)))
                      (funcall original-counter header latest)))
              (setf (symbol-function prefix-check)
                    (lambda (prefix path)
                      (when (boundp prefix-calls)
                        (incf (symbol-value prefix-calls)))
                      (funcall original-prefix-check prefix path)))
              (setf result
                    (edit-toml source (list target-key 0 "value") -1)))
          (setf (symbol-function counter) original-counter
                (symbol-function prefix-check) original-prefix-check))
        (expect (= header-count (symbol-value counter-calls)))
        (expect (<= (symbol-value prefix-calls) prefix-bound)))
      (let ((parsed (%edit-test-parse result)))
        (dotimes (index groups)
          (let* ((nested-key (format nil "nested-~D" index))
                 (nested-table (gethash nested-key parsed))
                 (children (gethash "child" nested-table))
                 (item-key (format nil "item-~D" index))
                 (items (gethash item-key parsed))
                 (item-value (if (= index target-index) -1 index)))
            (expect (= 1 (length children)))
            (expect (= index (gethash "value" (aref children 0))))
            (expect (= 1 (length items)))
            (expect (= item-value (gethash "value" (aref items 0)))))))))
  (it "edits and deletes inline-table fields while retaining separators"
    (let* ((source
             (%edit-test-bytes
              "settings = { first = 1, middle = 2, last = 3 }~%"))
           (edited (edit-toml source (list "settings" "middle") 4))
           (without-first (delete-toml source (list "settings" "first")))
           (without-last (delete-toml source (list "settings" "last"))))
      (expect (string= (%edit-test-format
                        "settings = { first = 1, middle = 4, last = 3 }~%")
                       (%edit-test-text edited)))
      (expect (= 4 (%edit-test-value edited (list "settings" "middle"))))
      (expect (string= (%edit-test-format
                        "settings = { middle = 2, last = 3 }~%")
                       (%edit-test-text without-first)))
      (expect (string= (%edit-test-format
                        "settings = { first = 1, middle = 2 }~%")
                       (%edit-test-text without-last)))))
  (it "leaves BOM and CRLF input bytes unchanged when deletion fails"
    (let* ((source
             (%edit-test-bytes
              (with-output-to-string (stream)
                (write-char (code-char #xfeff) stream)
                (write-string "name = \"old\" # keep" stream)
                (write-char #\Return stream)
                (write-char #\Newline stream))))
           (snapshot (copy-seq source)))
      (expect (signals toml-format-preservation-error
                (delete-toml source (list "name"))))
      (expect (equalp snapshot source))))
  (it "rejects a non-octet vector without changing it"
    (let* ((source (vector 110 97 256 101))
           (snapshot (copy-seq source)))
      (expect (signals type-error
                (edit-toml source (list "name") "new")))
      (expect (equalp snapshot source))))
  (it "splices values after multibyte UTF-8 text at the right byte offset"
    (let* ((source (%edit-test-bytes "label = \"猫🙂\"~%count = 1~%"))
           (result (edit-toml source (list "count") 2)))
      (expect (string= (%edit-test-format
                        "label = \"猫🙂\"~%count = 2~%")
                       (%edit-test-text result)))
      (expect (= 2 (%edit-test-value result (list "count"))))))
  (it "accepts string and vector paths and rejects invalid ones"
  (let* ((source (%edit-test-bytes "name = 1~%"))
         (string-path (edit-toml source "name" 2))
         (vector-path (edit-toml source (vector "name") 3)))
    (expect (= 2 (%edit-test-value string-path (list "name"))))
    (expect (= 3 (%edit-test-value vector-path (list "name"))))
    (expect (signals toml-format-preservation-error
              (edit-toml source nil 4)))
    (expect (signals toml-format-preservation-error
              (edit-toml source (list -1) 4)))
    (expect (signals toml-format-preservation-error
              (edit-toml source (make-symbol "name") 4)))))
  (it "uses adjacent line endings when inserting around section boundaries"
  (let* ((crlf (coerce (list #\Return #\Newline) 'string))
         (source (sb-ext:string-to-octets
                  (concatenate 'string "[server]" crlf "name = 1" crlf)
                  :external-format :utf-8))
         (crlf-result (edit-toml source (list "version") 2))
         (lf-source (%edit-test-bytes "[server]~%name = 1~%"))
         (lf-result (edit-toml lf-source (list "version") 2))
         (empty-result (edit-toml (%edit-test-bytes "") (list "name") 1))
         (unterminated (edit-toml (%edit-test-bytes "name = 1")
                                  (list "other") 2)))
    (expect (string= (concatenate 'string "version = 2" crlf
                                  "[server]" crlf "name = 1" crlf)
                     (%edit-test-text crlf-result)))
    (expect (string= (%edit-test-format "version = 2~%[server]~%name = 1~%")
                     (%edit-test-text lf-result)))
    (expect (string= (%edit-test-format "name = 1~%")
                     (%edit-test-text empty-result)))
    (expect (string= (%edit-test-format "name = 1~%other = 2~%")
                     (%edit-test-text unterminated)))))
  (it "adds the first item to empty arrays and inline tables"
  (let* ((array-source (%edit-test-bytes "values = []~%"))
         (array-result (edit-toml array-source (list "values" 0) 1))
         (inline-source (%edit-test-bytes "settings = {}~%"))
         (inline-result (edit-toml inline-source (list "settings" "mode") 1)))
    (expect (string= (%edit-test-format "values = [1]~%")
                     (%edit-test-text array-result)))
    (expect (= 1 (%edit-test-value array-result (list "values" 0))))
    (expect (string= (%edit-test-format "settings = {mode = 1}~%")
                     (%edit-test-text inline-result)))
    (expect (= 1 (%edit-test-value inline-result (list "settings" "mode"))))))
  (it "scans escaped keys and counts two-byte UTF-8 offsets"
  (let* ((source (%edit-test-bytes "\"é\" = 1~%\"line\\nkey\" = 2~%"))
         (first-result (edit-toml source (list "é") 3))
         (key (format nil "line~%key"))
         (result (edit-toml first-result (list key) 4)))
    (expect (string= (%edit-test-format "\"é\" = 3~%\"line\\nkey\" = 4~%")
                     (%edit-test-text result)))
    (expect (= 3 (%edit-test-value result (list "é"))))
    (expect (= 4 (%edit-test-value result (list key))))))
  (it "checks semantic type mismatches and overlapping byte edits"
  (let* ((equal-value
           (symbol-function (find-symbol "%EDIT-VALUE-EQUAL-P" "CL-TOML-KIT")))
         (apply-bytes
           (symbol-function (find-symbol "%EDIT-APPLY-BYTES" "CL-TOML-KIT")))
         (left (make-hash-table :test (function equal)))
         (same (make-hash-table :test (function equal)))
         (empty (make-hash-table :test (function equal)))
         (other (make-hash-table :test (function equal))))
    (setf (gethash "left" left) 1
          (gethash "left" same) 1
          (gethash "right" other) 1)
    (expect (funcall equal-value left same))
    (expect (not (funcall equal-value left empty)))
    (expect (not (funcall equal-value left other)))
    (expect (not (funcall equal-value left 1)))
    (expect (funcall equal-value #(1) #(1)))
    (expect (not (funcall equal-value #(1) #(2))))
    (expect (not (funcall equal-value #(1 2) #(1))))
    (expect (not (funcall equal-value #() nil)))
    (expect (signals toml-format-preservation-error
              (funcall apply-bytes #(1 2 3)
                       (list (list 0 2 #(9))
                             (list 1 3 #(8))))))))
  (it "decodes Unicode escapes and scans quoted key delimiters"
  (let* ((source
           (%edit-test-bytes
            "\"quote\\\"key\" = 1~%\"small\\u00e9\" = 2~%\"face\\U0001F642\" = 3~%'literal' = 4~%"))
         (quoted (edit-toml source (list "quote\"key") 5))
         (small (edit-toml quoted (list "smallé") 6))
         (face (edit-toml small (list "face🙂") 7))
         (result (edit-toml face (list "literal") 8)))
    (expect (string=
             (%edit-test-format
              "\"quote\\\"key\" = 5~%\"small\\u00e9\" = 6~%\"face\\U0001F642\" = 7~%'literal' = 8~%")
             (%edit-test-text result)))
    (expect (= 5 (%edit-test-value result (list "quote\"key"))))
    (expect (= 6 (%edit-test-value result (list "smallé"))))
    (expect (= 7 (%edit-test-value result (list "face🙂"))))
    (expect (= 8 (%edit-test-value result (list "literal"))))))
  (it "uses CRLF when adding a key inside an existing table"
  (let* ((crlf (coerce (list #\Return #\Newline) 'string))
         (source (sb-ext:string-to-octets
                  (concatenate 'string "[server]" crlf "name = 1" crlf)
                  :external-format :utf-8))
         (result (edit-toml source (list "server" "port") 2)))
    (expect
     (string= (concatenate 'string "[server]" crlf "name = 1" crlf "port = 2" crlf)
              (%edit-test-text result)))
    (expect (= 2 (%edit-test-value result (list "server" "port"))))))
  (it "routes byte-editor replacement and deletion options"
  (let* ((source (%edit-test-bytes "name = 1~%"))
         (replaced (edit-toml-bytes source (list "name") 2))
         (deleted (edit-toml-bytes replaced (list "name") nil :delete t)))
    (expect (= 2 (%edit-test-value replaced (list "name"))))
    (expect (string= "" (%edit-test-text deleted)))
    (expect (= 0 (hash-table-count (%edit-test-parse deleted))))))
  (it "deletes the only inline entry and the final array item"
  (let* ((inline-source (%edit-test-bytes "settings = {only = 1}~%"))
         (inline-result (delete-toml inline-source (list "settings" "only")))
         (array-source (%edit-test-bytes "values = [1, 2, 3]~%"))
         (array-result (delete-toml array-source (list "values" 2))))
    (expect (string= (%edit-test-format "settings = {}~%")
                     (%edit-test-text inline-result)))
    (expect (string= (%edit-test-format "values = [1, 2]~%")
                     (%edit-test-text array-result)))
    (expect (equalp #(1 2) (%edit-test-value array-result (list "values"))))))
  (it "rejects ambiguous additions and absent deletions without changing bytes"
    (let* ((source
              (%edit-test-bytes
               "[[products]]~%name = 1~%[[products]]~%name = 2~%"))
           (original (copy-seq source)))
      (expect
       (signals error
         (edit-toml source (list "products" "extra") 3)))
      (expect (equalp original source))
      (expect (signals error (delete-toml source (list "missing"))))
      (expect (equalp original source))))
  (it "checks scanner and line-ending boundaries"
    (let* ((char-at-limit
              (symbol-function (find-symbol "%EDIT-CHAR" "CL-TOML-KIT")))
           (key-component
             (symbol-function
              (find-symbol "%EDIT-SCAN-KEY-COMPONENT" "CL-TOML-KIT")))
           (scan-string
             (symbol-function (find-symbol "%EDIT-SCAN-STRING" "CL-TOML-KIT")))
           (scan-array
             (symbol-function (find-symbol "%EDIT-SCAN-ARRAY-NODE" "CL-TOML-KIT")))
           (scan-inline
             (symbol-function (find-symbol "%EDIT-SCAN-INLINE-NODE" "CL-TOML-KIT")))
           (skip-trivia
             (symbol-function
              (find-symbol "%EDIT-SKIP-COMMENT-AND-TRIVIA" "CL-TOML-KIT")))
           (line-ending
             (symbol-function (find-symbol "%EDIT-LINE-ENDING" "CL-TOML-KIT")))
           (comment (format nil "# comment~%  value"))
           (crlf (format nil "a~C~Cb" #\Return #\Newline))
           (next-crlf (format nil "a~C~C" #\Return #\Newline)))
      (expect (null (funcall char-at-limit "x" 1 1)))
      (expect
       (equal (multiple-value-list (funcall key-component "bare" 0 4))
              (list "bare" 4)))
      (expect (= 3 (funcall scan-string "\"x\"" 0 3)))
      (expect (= 7 (funcall scan-string "\"\"\"x\"\"\"" 0 7)))
      (expect (signals error (funcall scan-string "\"open" 0 5)))
      (expect
       (= (position #\v comment)
          (funcall skip-trivia comment 0 (length comment))))
      (expect (signals error (funcall key-component "?" 0 1)))
      (expect (signals error (funcall scan-array "[1" 0 2 nil nil)))
      (expect (signals error (funcall scan-inline "{a=1" 0 4 nil nil)))
      (expect
       (string= (format nil "~C~C" #\Return #\Newline)
                (funcall line-ending crlf 3)))
      (expect
       (string= (string #\Newline)
                (funcall line-ending (format nil "a~%b") 2)))
      (expect
       (string= (format nil "~C~C" #\Return #\Newline)
                (funcall line-ending next-crlf 0)))
      (expect
       (string= (string #\Newline)
                (funcall line-ending "abc" 0)))))
  (it "appends to a nonempty array while preserving its trailing comma"
    (let* ((source (%edit-test-bytes "values = [1, 2,]~%"))
           (result (edit-toml source (list "values" 2) 3)))
      (expect
       (string= (%edit-test-format "values = [1, 2, 3,]~%")
                (%edit-test-text result)))
      (expect (equalp #(1 2 3) (%edit-test-value result (list "values"))))))
  (it "validates recursive semantic array updates"
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
       (equalp #(9 2) (funcall change (vector 1 2) (list 0) 9 nil)))
      (expect
       (equalp #(2) (funcall change (vector 1 2) (list 0) nil t)))
      (expect (signals error (funcall change 1 (list "key") 2 nil)))
      (expect (signals error (funcall change table (list 0) 2 nil)))
      (expect (signals error (funcall change table (list "missing") nil t)))
      (expect (signals error (funcall change #(1) (list -1) 0 nil))))))
