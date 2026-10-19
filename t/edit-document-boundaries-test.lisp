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
    (expect (string= (%edit-test-format "version = 2~%[server]~%name = 1~%")
                     (%edit-test-text lf-result)))))
  (it "preserves line endings when appending to empty or unterminated documents"
  (let* ((empty-result (edit-toml (%edit-test-bytes "") (list "name") 1))
         (unterminated (edit-toml (%edit-test-bytes "name = 1")
                                  (list "other") 2)))
    (expect (string= (%edit-test-format "name = 1~%")
                     (%edit-test-text empty-result)))
    (expect (string= (%edit-test-format "name = 1~%other = 2~%")
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
