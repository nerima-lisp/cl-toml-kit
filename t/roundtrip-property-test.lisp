(in-package #:cl-toml-kit/test)
(describe "TOML generated round trips"
  (it-property "round-trips generated parser documents"
      ((document (toml-test-parser-document-generator)))
    (destructuring-bind (source expected) document
      (let* ((parsed (parse source))
             (rewritten (encode parsed))
             (reparsed (parse rewritten)))
        (expect (toml-test-value= expected parsed))
        (expect (toml-test-value= expected reparsed))
        (expect (toml-test-value= parsed reparsed)))))
  (it-property "changes a nested integer to a generated TOML value"
      ((old (cl-weave:gen-integer :min -100000 :max 100000))
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
    (let* ((source
             (%edit-test-bytes
              (format nil "keep = ~D~%[section]~%value = ~D~%unrelated = \"unchanged\"~%"
                      old old)))
           (edited (edit-toml source (list "section" "value") replacement))
           (document (%edit-test-parse edited))
           (section (gethash "section" document))
           (actual (gethash "value" section)))
      (expect (= old (gethash "keep" document)))
      (expect (string= "unchanged" (gethash "unrelated" section)))
      (expect (not (integerp actual)))
      (expect (toml-test-value= replacement actual)))))
