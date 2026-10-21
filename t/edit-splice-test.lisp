(in-package #:cl-toml-kit/test)

(describe "format-preserving TOML edits"
  (it "edits an inline table leaf and keeps the inline form"
    (let* ((source (%edit-test-bytes "config = { enabled = true, count = 2 } # keep~%"))
           (result (edit-toml source '("config" "count") 3)))
      (expect (string= (%toml-test-format-text "config = { enabled = true, count = 3 } # keep~%")
                       (%edit-test-text result)))
      (let ((config (%edit-test-value result '("config"))))
        (expect (= 3 (gethash "count" config)))
        (expect (eq t (gethash "enabled" config))))))
  (it "adds inline table entries and retains added values"
    (let* ((source (%edit-test-bytes "config = { enabled = true, count = 2 }~%"))
           (added (edit-toml source '("config" "mode") "safe"))
           (deleted (delete-toml added '("config" "enabled"))))
      (expect (string= (%toml-test-format-text "config = { count = 2, mode = \"safe\" }~%")
                       (%edit-test-text deleted)))
      (let ((added-config (%edit-test-value added '("config")))
            (deleted-config (%edit-test-value deleted '("config"))))
        (expect (eq t (gethash "enabled" added-config)))
        (expect (= 2 (gethash "count" deleted-config))))))
  (it "deletes inline table entries and retains remaining values"
    (let* ((source (%edit-test-bytes "config = { enabled = true, count = 2 }~%"))
           (added (edit-toml source '("config" "mode") "safe"))
           (deleted (delete-toml added '("config" "enabled"))))
      (let ((deleted-config (%edit-test-value deleted '("config"))))
        (expect (string= "safe" (gethash "mode" deleted-config)))
        (expect (not (nth-value 1 (gethash "enabled" deleted-config)))))))
  (it "edits and appends array values"
    (let* ((source (%edit-test-bytes "values = [1, 2, 3]~%labels = [\"old\"]~%other = true~%"))
           (replaced (edit-toml source '("values" 1) 20))
           (with-label (edit-toml replaced '("values" 3) 4))
           (result (edit-toml with-label '("labels" 1) "new")))
      (expect (string= (%toml-test-format-text
                        (concatenate 'string
                                     "values = [1, 20, 3, 4]~%"
                                     "labels = [\"old\", \"new\"]~%other = true~%"))
                       (%edit-test-text result)))
      (expect (equalp #(1 20 3 4) (%edit-test-value result '("values"))))))
  (it "preserves labels and other keys after array edits"
    (let* ((source (%edit-test-bytes "values = [1, 2, 3]~%labels = [\"old\"]~%other = true~%"))
           (replaced (edit-toml source '("values" 1) 20))
           (with-label (edit-toml replaced '("values" 3) 4))
           (result (edit-toml with-label '("labels" 1) "new")))
      (expect (equalp #("old" "new") (%edit-test-value result '("labels"))))
      (expect (eq t (%edit-test-value result '("other"))))))
  (it "preserves trailing commas and indentation in multiline arrays"
    (let* ((source (%edit-test-bytes "values = [1,~%  2,~%]~%"))
           (added (edit-toml source '("values" 2) 3))
           (deleted (delete-toml added '("values" 0))))
      (expect (string= (%toml-test-format-text "values = [1,~%  2,~%  3,~%]~%")
                       (%edit-test-text added)))
      (expect (equalp #(1 2 3) (%edit-test-value added '("values"))))
      (expect (equalp #(2 3) (%edit-test-value deleted '("values"))))))
  (it "adds to a single trailing-comma array"
    (let* ((source (%edit-test-bytes "values = [1,]~%"))
           (added (edit-toml source '("values" 1) 2)))
      (expect (string= (%toml-test-format-text "values = [1, 2,]~%") (%edit-test-text added)))
      (expect (equalp #(1 2) (%edit-test-value added (list "values"))))))
  (it "deletes single trailing-comma array items"
    (let* ((source (%edit-test-bytes "values = [1,]~%"))
           (added (edit-toml source '("values" 1) 2))
           (deleted (delete-toml added '("values" 0)))
           (empty (delete-toml deleted '("values" 0))))
      (expect (equalp #(2) (%edit-test-value deleted '("values"))))
      (expect (and (equalp #() (%edit-test-value empty '("values")))
                   (string= (%toml-test-format-text "values = []~%")
                            (%edit-test-text empty))))))
  (it "does not join lines when deleting the final value"
    (let* ((source (%edit-test-bytes "first = 1~%last = 2~%next = 3~%"))
           (result (delete-toml source '("last"))))
      (expect (string= (%toml-test-format-text "first = 1~%next = 3~%")
                       (%edit-test-text result)))
      (expect (= 1 (%edit-test-value result '("first"))))
      (expect (= 3 (%edit-test-value result '("next"))))))
  (it "selects the requested array-of-tables element"
    (let* ((source (%edit-test-bytes
                    "[[products]]~%name = \"A\"~%~%[[products]]~%name = \"B\"~%"))
           (result (edit-toml source '("products" 1 "name") "B2")))
      (expect (string= (%toml-test-format-text
                        (concatenate 'string
                                     "[[products]]~%name = \"A\"~%~%"
                                     "[[products]]~%name = \"B2\"~%"))
                       (%edit-test-text result)))
      (let ((products (%edit-test-value result '("products"))))
        (expect (string= "A" (gethash "name" (aref products 0))))
        (expect (string= "B2" (gethash "name" (aref products 1)))))))
  (it "rejects additions that would re-home a dotted key"
    (let ((source (%edit-test-bytes "server.host = \"example\"~%")))
      (expect (signals toml-format-preservation-error
                (edit-toml source '("server" "port") 8080)))
      (expect (string= (%toml-test-format-text "server.host = \"example\"~%")
                       (%edit-test-text source)))))
  (it-each (("# keep~%name = \"old\"~%" "name")
            ("name = \"old\" # keep~%" "name"))
      "rejects scalar deletion that would lose a comment"
      (source key)
    (let ((bytes (%edit-test-bytes source)))
      (expect (signals toml-format-preservation-error
                (delete-toml bytes (list key))))
      (expect (string= (%toml-test-format-text source) (%edit-test-text bytes)))))
  (it "rejects array deletion that would remove an element comment"
    (let ((source (%edit-test-bytes "values = [1, # first~%  2]~%")))
      (expect (signals toml-format-preservation-error
                (delete-toml source '("values" 0))))
      (expect (string= (%toml-test-format-text "values = [1, # first~%  2]~%")
                       (%edit-test-text source)))))
  (it "inserts section keys before trailing trivia"
    (let* ((source (%edit-test-bytes
                    "[server]~%name = \"x\"~%~%# section note~%[other]~%value = 1~%"))
           (result (edit-toml source '("server" "port") 8080)))
      (expect (string= (%toml-test-format-text
                        (concatenate 'string
                                     "[server]~%name = \"x\"~%port = 8080~%"
                                     "~%# section note~%[other]~%value = 1~%"))
                       (%edit-test-text result)))
      (expect (= 8080 (%edit-test-value result '("server" "port"))))))
  (it "rejects array insertion after a trailing comment"
    (let ((source (%edit-test-bytes "values = [1, 2 # keep~%]~%")))
      (expect (signals toml-format-preservation-error
                (edit-toml source '("values" 2) 3)))
      (expect (string= (%toml-test-format-text "values = [1, 2 # keep~%]~%")
                       (%edit-test-text source)))))
  (it "uses the preceding line ending for a root insertion"
    (let* ((crlf (coerce (list #\Return #\Newline) 'string))
           (source (sb-ext:string-to-octets
                    (concatenate 'string "first = 1" (string #\Newline)
                                 "second = 2" (string #\Newline)
                                 "[server]" crlf
                                 "name = \"x\"" crlf)
                    :external-format :utf-8))
           (result (edit-toml source '("third") 3)))
      (expect (string= (concatenate 'string "first = 1" (string #\Newline)
                                    "second = 2" (string #\Newline)
                                    "third = 3" (string #\Newline)
                                    "[server]" crlf
                                    "name = \"x\"" crlf)
                       (%edit-test-text result)))))
  (it "quotes a dotted string key when inserting it"
    (let* ((source (%edit-test-bytes "other = 1~%"))
           (result (edit-toml source '("a.b") "value")))
      (expect (string= (%toml-test-format-text "other = 1~%\"a.b\" = \"value\"~%")
                       (%edit-test-text result)))
      (expect (string= "value" (%edit-test-value result '("a.b"))))))
  (it "rejects an array addition beyond the next index without changing the source"
    (let* ((source (%edit-test-bytes "values = [1]~%"))
           (snapshot (copy-seq source))
           (path (list "values" 3))
           (condition
             (handler-case
                 (edit-toml source path 2)
               (toml-format-preservation-error (condition) condition))))
      (expect (and (typep condition (quote toml-format-preservation-error))
                   (equal path (toml-format-preservation-error-path condition))
                   (string= "Adding this path would require an ambiguous table or array structure"
                            (toml-format-preservation-error-message condition))))
      (expect (equalp snapshot source)))))
