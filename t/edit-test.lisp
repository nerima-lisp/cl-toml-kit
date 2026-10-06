(in-package #:cl-toml-kit/test)

(defun %edit-test-format (text)
  (if (search "~%" text) (format nil text) text))

(defun %edit-test-bytes (text)
  (sb-ext:string-to-octets (%edit-test-format text) :external-format :utf-8))

(defun %edit-test-text (bytes)
  (sb-ext:octets-to-string bytes :external-format :utf-8))

(defun %edit-test-parse (bytes)
  (let ((start (if (and (>= (length bytes) 3)
                        (= (aref bytes 0) 239)
                        (= (aref bytes 1) 187)
                        (= (aref bytes 2) 191))
                   3 0)))
    (parse (sb-ext:octets-to-string (subseq bytes start)
                                    :external-format :utf-8))))

(defun %edit-test-value (bytes path)
  (let ((value (%edit-test-parse bytes)))
    (dolist (component path value)
      (setf value (if (integerp component)
                      (aref value component)
                      (gethash component value))))))

(describe "format-preserving TOML edits"
  (it "replaces a value without changing comments, spacing, or CRLF"
    (let* ((source (%edit-test-bytes
                    (format nil "# top~C~Cother = 7~C~Cname = \"old\"  # keep~C~C"
                            #\Return #\Newline #\Return #\Newline #\Return #\Newline)))
           (result (edit-toml source '("name") "new")))
      (expect (string= (format nil "# top~C~Cother = 7~C~Cname = \"new\"  # keep~C~C"
                               #\Return #\Newline #\Return #\Newline #\Return #\Newline)
                       (%edit-test-text result)))
      (expect (= 7 (gethash "other" (%edit-test-parse result))))
      (expect (string= "new" (%edit-test-value result '("name"))))))
  (it "preserves a UTF-8 BOM"
    (let* ((source (concatenate '(vector (unsigned-byte 8))
                                #(239 187 191)
                                (%edit-test-bytes
                                 (format nil "name = \"old\"~C~C"
                                         #\Return #\Newline))))
           (result (edit-toml source '("name") "new")))
      (expect (equalp result
                      (concatenate '(vector (unsigned-byte 8))
                                   #(239 187 191)
                                   (%edit-test-bytes
                                    (format nil "name = \"new\"~C~C"
                                            #\Return #\Newline)))))
      (expect (string= "new" (%edit-test-value result '("name"))))))
  (it-each (("path = 'C:\\old\\#file' # keep~%"
             "path = 'new' # keep~%")
            ("text = \"\"\"old~%text\"\"\" # keep~%"
             "text = \"\"\"new\"\"\" # keep~%")
            ("text = '''old~%text''' # keep~%"
             "text = '''new''' # keep~%"))
      "preserves string delimiters while replacing ~S"
      (source expected)
    (let* ((path (if (search "path =" source) '("path") '("text")))
           (result (edit-toml (%edit-test-bytes source) path "new")))
      (expect (string= (%edit-test-format expected) (%edit-test-text result)))
      (expect (string= "new" (%edit-test-value result path)))))
  (it "edits an inline table leaf and keeps the inline form"
    (let* ((source (%edit-test-bytes "config = { enabled = true, count = 2 } # keep~%"))
           (result (edit-toml source '("config" "count") 3)))
      (expect (string= (%edit-test-format "config = { enabled = true, count = 3 } # keep~%")
                       (%edit-test-text result)))
      (let ((config (%edit-test-value result '("config"))))
        (expect (= 3 (gethash "count" config)))
        (expect (eq t (gethash "enabled" config))))))
  (it "adds and deletes inline table entries"
    (let* ((source (%edit-test-bytes "config = { enabled = true, count = 2 }~%"))
           (added (edit-toml source '("config" "mode") "safe"))
           (deleted (delete-toml added '("config" "enabled"))))
      (expect (string= (%edit-test-format "config = { count = 2, mode = \"safe\" }~%")
                       (%edit-test-text deleted)))
      (let ((added-config (%edit-test-value added '("config")))
            (deleted-config (%edit-test-value deleted '("config"))))
        (expect (eq t (gethash "enabled" added-config)))
        (expect (= 2 (gethash "count" deleted-config)))
        (expect (string= "safe" (gethash "mode" deleted-config)))
        (expect (not (nth-value 1 (gethash "enabled" deleted-config)))))))
  (it "edits and appends array values without changing other keys"
    (let* ((source (%edit-test-bytes "values = [1, 2, 3]~%labels = [\"old\"]~%other = true~%"))
           (replaced (edit-toml source '("values" 1) 20))
           (with-label (edit-toml replaced '("values" 3) 4))
           (result (edit-toml with-label '("labels" 1) "new")))
      (expect (string= (%edit-test-format "values = [1, 20, 3, 4]~%labels = [\"old\", \"new\"]~%other = true~%")
                       (%edit-test-text result)))
      (expect (equalp #(1 20 3 4) (%edit-test-value result '("values"))))
      (expect (equalp #("old" "new") (%edit-test-value result '("labels"))))
      (expect (eq t (%edit-test-value result '("other"))))))
  (it "preserves trailing commas and indentation in multiline arrays"
    (let* ((source (%edit-test-bytes "values = [1,~%  2,~%]~%"))
           (added (edit-toml source '("values" 2) 3))
           (deleted (delete-toml added '("values" 0))))
      (expect (string= (%edit-test-format "values = [1,~%  2,~%  3,~%]~%")
                       (%edit-test-text added)))
      (expect (equalp #(1 2 3) (%edit-test-value added '("values"))))
      (expect (equalp #(2 3) (%edit-test-value deleted '("values"))))))
  (it "handles a single trailing-comma array element"
    (let* ((source (%edit-test-bytes "values = [1,]~%"))
           (added (edit-toml source '("values" 1) 2))
           (deleted (delete-toml added '("values" 0)))
           (empty (delete-toml deleted '("values" 0))))
      (expect (string= (%edit-test-format "values = [1, 2,]~%")
                       (%edit-test-text added)))
      (expect (equalp #(1 2) (%edit-test-value added '("values"))))
      (expect (equalp #(2) (%edit-test-value deleted '("values"))))
      (expect (equalp #() (%edit-test-value empty '("values"))))))
  (it "does not join lines when deleting the final value"
    (let* ((source (%edit-test-bytes "first = 1~%last = 2~%next = 3~%"))
           (result (delete-toml source '("last"))))
      (expect (string= (%edit-test-format "first = 1~%next = 3~%")
                       (%edit-test-text result)))
      (expect (= 1 (%edit-test-value result '("first"))))
      (expect (= 3 (%edit-test-value result '("next"))))))
  (it "replaces a value with an empty string"
    (let* ((source (%edit-test-bytes "name = \"old\"~%other = 1~%"))
           (result (edit-toml source '("name") "")))
      (expect (string= (%edit-test-format "name = \"\"~%other = 1~%")
                       (%edit-test-text result)))
      (expect (string= "" (%edit-test-value result '("name"))))
      (expect (= 1 (%edit-test-value result '("other"))))))
  (it "adds a table leaf using inline-table serialization"
    (let ((settings (make-hash-table :test 'equal)))
      (setf (gethash "mode" settings) "safe")
      (let* ((source (%edit-test-bytes "[server]~%name = \"example\"~%"))
             (result (edit-toml source '("server" "settings") settings))
             (server (%edit-test-value result '("server"))))
        (expect (string= (%edit-test-format "[server]~%name = \"example\"~%settings = { mode = \"safe\" }~%")
                         (%edit-test-text result)))
        (expect (string= "example" (gethash "name" server)))
        (expect (string= "safe" (gethash "mode" (gethash "settings" server)))))))
  (it "selects the requested array-of-tables element"
    (let* ((source (%edit-test-bytes
                    "[[products]]~%name = \"A\"~%~%[[products]]~%name = \"B\"~%"))
           (result (edit-toml source '("products" 1 "name") "B2")))
      (expect (string= (%edit-test-format "[[products]]~%name = \"A\"~%~%[[products]]~%name = \"B2\"~%")
                       (%edit-test-text result)))
      (let ((products (%edit-test-value result '("products"))))
        (expect (string= "A" (gethash "name" (aref products 0))))
        (expect (string= "B2" (gethash "name" (aref products 1)))))))
  (it "keeps dotted-key spacing when replacing its value"
    (let* ((source (%edit-test-bytes "server . port = 8080 # keep~%"))
           (result (edit-toml source '("server" "port") 9090)))
      (expect (string= (%edit-test-format "server . port = 9090 # keep~%")
                       (%edit-test-text result)))
      (expect (= 9090 (%edit-test-value result '("server" "port"))))))
  (it "rejects additions that would re-home a dotted key"
    (let ((source (%edit-test-bytes "server.host = \"example\"~%")))
      (expect (signals toml-format-preservation-error
                (edit-toml source '("server" "port") 8080)))
      (expect (string= (%edit-test-format "server.host = \"example\"~%")
                       (%edit-test-text source)))))
  (it "replaces a space-separated date-time as one scalar value"
    (let* ((source (%edit-test-bytes "created = 1979-05-27 07:32:00 # keep~%"))
           (result (edit-toml source '("created") 42)))
      (expect (string= (%edit-test-format "created = 42 # keep~%")
                       (%edit-test-text result)))
      (expect (= 42 (%edit-test-value result '("created"))))))
  (it "rejects a replacement that cannot retain a literal delimiter"
    (let ((source (%edit-test-bytes "text = '''old'''~%")))
      (expect (signals toml-format-preservation-error
                (edit-toml source '("text") "bad'''value")))
      (expect (string= (%edit-test-format "text = '''old'''~%")
                       (%edit-test-text source)))))
  (it "rejects duplicate definitions before editing"
    (let ((source (%edit-test-bytes "name = 1~%name = 2~%")))
      (expect (signals toml-parse-error
                (edit-toml source '("name") 3)))
      (expect (string= (%edit-test-format "name = 1~%name = 2~%")
                       (%edit-test-text source)))))
  (it "rejects an ambiguous structural edit without changing the input"
    (let ((source (%edit-test-bytes "[[products]]~%name = \"A\"~%")))
      (expect (signals toml-format-preservation-error
                (edit-toml source '("products" "name") "B")))
      (expect (string= (%edit-test-format "[[products]]~%name = \"A\"~%")
                       (%edit-test-text source))))))
