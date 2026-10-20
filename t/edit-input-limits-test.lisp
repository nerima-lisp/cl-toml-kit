(in-package #:cl-toml-kit/test)
(describe "editor input limits"
  (it "rejects byte vectors above the configured byte limit"
    (let* ((*toml-max-input-bytes* 7)
           (source (%edit-test-bytes "name = 1"))
           (condition
             (handler-case
                 (edit-toml source "name" 2)
               (toml-format-preservation-error (condition) condition))))
      (expect (and condition
                   (string= "TOML input byte limit exceeded"
                            (toml-format-preservation-error-message
                             condition))))))
  (it "rejects decoded text above the character limit"
    (let* ((text "name = \"é\"")
           (source (%edit-test-bytes text))
           (*toml-max-input-characters* (1- (length text)))
           (condition
             (handler-case
                 (edit-toml source "name" "new")
               (toml-format-preservation-error (condition) condition))))
      (expect (> (length source) (length text)))
      (expect (and condition
                   (string= "TOML input character limit exceeded"
                            (toml-format-preservation-error-message
                             condition))))))
  (it "accepts input exactly at both configured limits"
    (let* ((text "name = 1")
           (source (%edit-test-bytes text))
           (*toml-max-input-bytes* (length source))
           (*toml-max-input-characters* (length text))
           (result (edit-toml source "name" 2)))
      (expect (= 2 (%edit-test-value result (list "name")))))))

