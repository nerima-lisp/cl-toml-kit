(in-package #:cl-toml-kit/test)

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
      (expect (string= (%toml-test-format-text expected) (%edit-test-text result)))
      (expect (string= "new" (%edit-test-value result path)))))
  (it-each (("text = \"\"\"a \" b\"\"\"~%"
             "text = \"\"\"new\"\"\"~%")
            ("text = \"\"\"a \"\" b\"\"\"~%"
             "text = \"\"\"new\"\"\"~%")
            ("text = '''a ' b'''~%"
             "text = '''new'''~%")
            ("text = '''a '' b'''~%"
             "text = '''new'''~%"))
      "edits multiline strings containing one or two embedded quotes"
      (source expected)
    (let ((result (edit-toml (%edit-test-bytes source) '("text") "new")))
      (expect (string= (%toml-test-format-text expected) (%edit-test-text result)))
      (expect (string= "new" (%edit-test-value result '("text"))))))
  (it-edit-table
    "preserves edited text and parsed values for ~S at path ~S"
    (("name = \"old\"~%other = 1~%" ("name") ""
     "name = \"\"~%other = 1~%" "")
    ("server . port = 8080 # keep~%" ("server" "port") 9090
     "server . port = 9090 # keep~%" 9090)
    ("created = 1979-05-27 07:32:00 # keep~%" ("created") 42
     "created = 42 # keep~%" 42)
    ("[server]~%name = \"example\"~%" ("server" "settings")
     #.(let ((settings (make-hash-table :test 'equal)))
         (setf (gethash "mode" settings) "safe")
         settings)
     "[server]~%name = \"example\"~%settings = { mode = \"safe\" }~%"
     #.(let ((settings (make-hash-table :test 'equal)))
         (setf (gethash "mode" settings) "safe")
         settings))
    ("\"a\\x41b\" = 1~%" ("aAb") 2
     "\"a\\x41b\" = 2~%" 2)))
  (it "keeps other root values when replacing with an empty string"
      (let ((result (edit-toml (%edit-test-bytes "name = \"old\"~%other = 1~%")
                               '("name") "")))
        (expect (= 1 (%edit-test-value result '("other"))))))
  (it "retains existing section leaves when inserting a table leaf"
    (let ((settings (make-hash-table :test 'equal)))
      (setf (gethash "mode" settings) "safe")
      (let* ((source (%edit-test-bytes "[server]~%name = \"example\"~%"))
             (result (edit-toml source '("server" "settings") settings))
             (server (%edit-test-value result '("server"))))
        (expect (string= "example" (gethash "name" server))))))
  (it "rejects a replacement that cannot retain a literal delimiter"
    (let ((source (%edit-test-bytes "text = '''old'''~%")))
      (expect (signals toml-format-preservation-error
                (edit-toml source '("text") "bad'''value")))
      (expect (string= (%toml-test-format-text "text = '''old'''~%")
                       (%edit-test-text source)))))
  (it "rejects duplicate definitions before editing"
    (let ((source (%edit-test-bytes "name = 1~%name = 2~%")))
      (expect (signals toml-parse-error
                (edit-toml source '("name") 3)))
      (expect (string= (%toml-test-format-text "name = 1~%name = 2~%")
                       (%edit-test-text source)))))
  (it "rejects an ambiguous structural edit without changing the input"
    (let ((source (%edit-test-bytes "[[products]]~%name = \"A\"~%")))
      (expect (signals toml-format-preservation-error
                (edit-toml source '("products" "name") "B")))
      (expect (string= (%toml-test-format-text "[[products]]~%name = \"A\"~%")
                       (%edit-test-text source)))))
  (it "rejects a multiline replacement that changes the parsed value"
    (let ((source (%edit-test-bytes "text = '''old'''~%")))
      (expect (signals toml-format-preservation-error
                (edit-toml source '("text") (format nil "~%new"))))
      (expect (string= (%toml-test-format-text "text = '''old'''~%")
                       (%edit-test-text source)))))
  (it "resets nested array-table indices for each parent element"
    (let* ((source (%edit-test-bytes
                    (concatenate 'string
                                 "[[a]]~%[[a.b]]~%name = \"a0b0\"~%[[a]]~%"
                                 "[[a.b]]~%name = \"a1b0\"~%[[a.b]]~%name = \"a1b1\"~%")))
           (result (edit-toml source '("a" 1 "b" 1 "name") "changed"))
           (a (%edit-test-value result '("a"))))
      (expect (string= "a0b0" (gethash "name" (aref (gethash "b" (aref a 0)) 0))))
      (expect (string= "a1b0" (gethash "name" (aref (gethash "b" (aref a 1)) 0))))
      (expect (string= "changed" (gethash "name" (aref (gethash "b" (aref a 1)) 1))))))
  (it "escapes replacement strings and preserves their parsed value"
    (let* ((source (%edit-test-bytes "text = \"old\"~%"))
           (value (format nil "line~%quote\""))
           (result (edit-toml source '("text") value)))
      (expect (string= value (%edit-test-value result '("text"))))))
  (it "does not treat a tilde in test data as a format directive"
    (let* ((source (%edit-test-bytes "text = \"old\" # a ~ b~%"))
           (result (edit-toml source '("text") "new ~ value")))
      (expect (string= (%toml-test-format-text "text = \"new ~ value\" # a ~ b~%")
                       (%edit-test-text result)))))
  (it "does not turn an omitted byte-editor value into deletion"
    (let ((source (%edit-test-bytes "name = \"old\"~%")))
      (expect (signals error (edit-toml source '("name"))))
      (expect (string= (%toml-test-format-text "name = \"old\"~%")
                       (%edit-test-text source)))))
  (it "rejects surrogate code points in literal-string replacements"
    (let* ((source (%edit-test-bytes "arr = [{ k = 'old' }, { k = 'old' }]"))
           (surrogate (code-char #xD800))
           (value (format nil "~C~C~C" #\n surrogate #\w))
           (condition
             (handler-case
                 (progn (edit-toml source (list "arr" 1 "k") value) nil)
               (error (condition) condition))))
      (expect (typep condition 'toml-encoding-error))
      (when (typep condition 'toml-encoding-error)
        (expect (equal (list "arr" 1 "k")
                       (toml-encoding-error-path condition))))))
  (it "rejects edit replacements that exceed the document nesting limit"
    (let* ((cl-toml-kit:*toml-max-nesting-depth* 2)
           (source (%edit-test-bytes "a = [1]"))
           (condition
             (handler-case
                 (progn (edit-toml source (list "a" 0) #(#(1))) nil)
               (error (condition) condition))))
      (expect (typep condition 'toml-encoding-error))
      (when (typep condition 'toml-encoding-error)
        (expect (equal (list "a" 0 0)
                       (toml-encoding-error-path condition))))
      (expect (string= "a = [1]" (%edit-test-text source)))))
  (it "applies writer limits and surrogate paths to additions"
    (let ((cl-toml-kit:*toml-max-nesting-depth* 2))
      (labels ((condition-for (source path value)
                 (handler-case
                     (progn (edit-toml (%edit-test-bytes source) path value) nil)
                   (error (condition) condition)))
               (expect-encoding-error (source path value expected-path)
                 (let ((condition (condition-for source path value)))
                   (expect (typep condition 'toml-encoding-error))
                   (when (typep condition 'toml-encoding-error)
                     (expect (equal expected-path
                                   (toml-encoding-error-path condition))))))
               (surrogate-string ()
                 (coerce (list #\n (code-char #xd800) #\w) 'string)))
        (expect-encoding-error "a = [1]~%"
                               '("a" 1)
                               #(#(1))
                               '("a" 1 0))
        (expect-encoding-error "a = { x = 1 }~%"
                               '("a" "y")
                               #(#(1))
                               '("a" "y" 0))
        (expect-encoding-error "a = 1~%"
                               '("b")
                               #(#(#(1)))
                               '("b" 0 0))
        (expect-encoding-error "a = [1]~%"
                               '("a" 1)
                               (surrogate-string)
                               '("a" 1))
        (expect-encoding-error "a = { x = 1 }~%"
                               '("a" "y")
                               (surrogate-string)
                               '("a" "y"))
        (expect-encoding-error "a = {}~%"
                               (list "a" (surrogate-string))
                               1
                               '("a" "n\\uD800w"))
        (expect-encoding-error "a = 1~%"
                               '("b")
                               (surrogate-string)
                               '("b"))
        (expect-encoding-error "a = 1~%"
                               (list "parent" (surrogate-string))
                               1
                               '("parent" "n\\uD800w"))))))
