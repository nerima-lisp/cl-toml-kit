(in-package #:cl-toml-kit/test)

(describe "editor regression boundaries"
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
  (it "uses CRLF and LF line endings when inserting before a section"
    (let* ((crlf (coerce (list #\Return #\Newline) 'string))
           (source (sb-ext:string-to-octets
                    (concatenate 'string "[server]" crlf "name = 1" crlf)
                    :external-format :utf-8))
           (crlf-result (edit-toml source (list "version") 2))
           (lf-source (%edit-test-bytes "[server]~%name = 1~%"))
           (lf-result (edit-toml lf-source (list "version") 2)))
      (expect (string= (concatenate 'string "version = 2" crlf
                                    "[server]" crlf "name = 1" crlf)
                       (%edit-test-text crlf-result)))
      (expect (string= (%toml-test-format-text "version = 2~%[server]~%name = 1~%")
                       (%edit-test-text lf-result)))))
  (it "preserves line endings when appending to empty or unterminated documents"
    (let* ((empty-result (edit-toml (%edit-test-bytes "") (list "name") 1))
           (unterminated (edit-toml (%edit-test-bytes "name = 1")
                                    (list "other") 2)))
      (expect (string= (%toml-test-format-text "name = 1~%")
                       (%edit-test-text empty-result)))
      (expect (string= (%toml-test-format-text "name = 1~%other = 2~%")
                       (%edit-test-text unterminated)))))
  (it "uses CRLF when adding a key inside an existing table"
    (let* ((crlf (coerce (list #\Return #\Newline) 'string))
           (source (sb-ext:string-to-octets
                    (concatenate 'string "[server]" crlf "name = 1" crlf)
                    :external-format :utf-8))
           (result (edit-toml source (list "server" "port") 2)))
      (expect
       (string= (concatenate 'string "[server]" crlf "name = 1" crlf "port = 2" crlf)
                (%edit-test-text result)))
      (expect (= 2 (%edit-test-value result (list "server" "port")))))))

(describe "editor helper defaults"
  (it "uses the default array-table counter path"
    (let* ((array-table-context
             (symbol-function
              (find-symbol "%EDIT-ARRAY-TABLE-CONTEXT" "CL-TOML-KIT")))
           (latest (make-hash-table :test (function equal)))
           (counts (make-hash-table :test (function equal)))
           (first-context
             (funcall array-table-context (list "products" "item") latest counts))
           (second-context
             (funcall array-table-context (list "products" "item") latest counts)))
      (expect (equal (list "products" "item" 0) first-context))
      (expect (equal (list "products" "item" 1) second-context))
      (expect (equal 2 (gethash (list "products" "item") counts)))))
  (it "scans an array-table header with the default counter path"
    (let* ((scan-header
             (symbol-function
              (find-symbol "%EDIT-SCAN-HEADER-LINE" "CL-TOML-KIT")))
           (latest (make-hash-table :test (function equal)))
           (counts (make-hash-table :test (function equal)))
           (text "[[products]]"))
      (multiple-value-bind (path next)
          (funcall scan-header text 0 0 (length text) latest counts)
        (expect (equal (list "products" 0) path))
        (expect (= (length text) next))
        (expect (equal 1 (gethash (list "products") counts))))))
  (it "uses the full text for the default line-ending position"
    (let* ((line-ending
             (symbol-function (find-symbol "%EDIT-LINE-ENDING" "CL-TOML-KIT")))
           (crlf (format nil "first~C~Csecond~C~C"
                         #\Return #\Newline #\Return #\Newline))
           (lf (format nil "first~%second~%")))
      (expect (string= (format nil "~C~C" #\Return #\Newline)
                       (funcall line-ending crlf)))
      (expect (string= (string #\Newline)
                       (funcall line-ending lf)))))
  (it "keeps malformed private document lines fail-closed"
    (dolist (case '(("[" nil "Invalid key while editing TOML")
                    ("[x" ("x") "Invalid table header")
                    ("[[x]" ("x") "Invalid table header")
                    ("x" ("x") "Assignment has no equals sign")))
      (let ((condition
              (handler-case
                  (progn (cl-toml-kit::%edit-scan-document (first case)) nil)
                (toml-format-preservation-error (condition) condition))))
        (expect (typep condition 'toml-format-preservation-error))
        (expect (equal (second case)
                       (toml-format-preservation-error-path condition)))
        (expect (string= (third case)
                         (toml-format-preservation-error-message condition)))))))
