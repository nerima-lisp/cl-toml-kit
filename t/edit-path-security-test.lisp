(in-package #:cl-toml-kit/test)
(describe "editor path security"
  (it "rejects dotted paths with a format-preservation condition"
    (let ((source (%edit-test-bytes "name = 1~%")))
      (expect (signals toml-format-preservation-error
                (edit-toml source (cons "name" "tail") 2)))))
  (it "rejects circular paths with a format-preservation condition"
    (let* ((source (%edit-test-bytes "name = 1~%"))
           (path (list "name")))
      (setf (cdr path) path)
      (expect (signals toml-format-preservation-error
                (edit-toml source path 2)))))
  (it "rejects paths above the configured component limit"
    (let* ((*toml-max-path-components* 1)
           (source (%edit-test-bytes "settings = { count = 1 }~%"))
           (condition
             (handler-case
                 (edit-toml source (list "settings" "count") 2)
               (toml-format-preservation-error (condition) condition))))
      (expect (and condition
                   (string= "TOML path component limit exceeded"
                            (toml-format-preservation-error-message condition)))))))

