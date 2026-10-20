(in-package #:cl-toml-kit/test)
(describe "TOML generated round trips"
  (it-property "preserves values through parse, write, and parse"
      ((table
         (toml-test-document-generator
          (cl-weave:gen-recursive
           (cl-weave:gen-one-of
            (cl-weave:gen-integer :min -1000 :max 1000)
            (cl-weave:gen-member
             (list "text" "日本語" t +toml-false+ 1.5d0)))
           #'%roundtrip-generated-values
           :max-depth 4))))
    (let* ((source (encode table))
           (parsed (parse source))
           (rewritten (encode parsed))
           (reparsed (parse rewritten)))
      (expect (toml-test-value= table parsed))
      (expect (toml-test-value= parsed reparsed))))
  (it-property "replaces generated values through edit-toml"
      ((old (cl-weave:gen-integer :min -100000 :max 100000))
       (replacement (cl-weave:gen-integer :min -100000 :max 100000)))
    (let* ((source
             (%edit-test-bytes
              (format nil "keep = ~D~%value = ~D~%" old old)))
           (edited (edit-toml source '("value") replacement))
           (document (%edit-test-parse edited)))
      (expect (= old (gethash "keep" document)))
      (expect
       (toml-test-value= replacement (gethash "value" document))))))
