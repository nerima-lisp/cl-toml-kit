(in-package #:cl-toml-kit/test)
(describe "editor path security"
  (it "rejects dotted paths with a format-preservation condition"
    (let* ((source (%edit-test-bytes "name = 1~%"))
           (condition
             (handler-case
                 (edit-toml source (cons "name" "tail") 2)
               (toml-format-preservation-error (condition) condition))))
      (expect (and condition
                   (string= "Path must be a finite proper list"
                            (toml-format-preservation-error-message
                             condition))))))
  (it "rejects circular paths with the component-limit message"
    (let* ((source (%edit-test-bytes "name = 1~%"))
           (path (list "name"))
           (condition nil))
      (setf (cdr path) path)
      (setf condition
            (handler-case
                (edit-toml source path 2)
              (toml-format-preservation-error (condition) condition)))
      (expect (and condition
                   (string= "TOML path component limit exceeded"
                            (toml-format-preservation-error-message
                             condition))))))
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
