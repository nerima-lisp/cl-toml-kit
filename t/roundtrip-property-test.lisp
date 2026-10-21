(in-package #:cl-toml-kit/test)
(describe "TOML generated round trips"
  (it-property "round-trips generated TOML documents"
      ((document (toml-test-source-document-generator)))
    (destructuring-bind (source expected) document
      (let* ((parsed (parse source))
             (rewritten (encode parsed))
             (reparsed (parse rewritten)))
        (expect (toml-test-value= expected parsed))
        (expect (toml-test-value= expected reparsed))
        (expect (toml-test-value= parsed reparsed)))))
  (it-property "changes a nested integer to a generated TOML value"
      ((levels
        (cl-weave:gen-vector
         (cl-weave:gen-integer :min 0 :max 99)
         :min-length 1 :max-length 4))
       (old (cl-weave:gen-integer :min -100000 :max 100000))
       (replacement
        (cl-weave:gen-map
         (lambda (value)
           (if (integerp value) (princ-to-string value) value))
         (cl-weave:gen-recursive
          (cl-weave:gen-one-of
           (cl-weave:gen-integer :min -100000 :max 100000)
           (cl-weave:gen-member (list "text" "日本語" t +toml-false+ 1.5d0)))
          (function toml-test-value-generator)
          :max-depth 4))))
    (let* ((table-path
             (append
              (list "section")
              (loop for level across levels
                    for index from 0
                    collect (format nil "level-~D-~D" index level))))
           (path (append table-path (list "value")))
           (header (format nil "[~{~A~^.~}]" table-path))
           (source
             (%edit-test-bytes
              (format nil "keep = ~D~%~A~%value = ~D~%unrelated = \"unchanged\"~%"
                      old header old)))
           (edited (edit-toml source path replacement))
           (document (%edit-test-parse edited))
           (leaf-table
             (loop with current = document
                   for key in table-path
                   do (setf current (gethash key current))
                   finally (return current)))
           (actual (gethash "value" leaf-table)))
      (expect (= old (gethash "keep" document)))
      (expect (string= "unchanged" (gethash "unrelated" leaf-table)))
      (expect (not (integerp actual)))
      (expect (toml-test-value= replacement actual)))))
