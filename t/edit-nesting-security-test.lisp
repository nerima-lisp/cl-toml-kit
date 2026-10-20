(in-package #:cl-toml-kit/test)
(defun %edit-test-nested-arrays (depth)
  (with-output-to-string (stream)
    (loop repeat depth do (write-char #\[ stream))
    (write-char #\0 stream)
    (loop repeat depth do (write-char #\] stream))))

(defun %edit-test-nested-inline-tables (depth)
  (with-output-to-string (stream)
    (loop repeat depth do (write-string "{a = " stream))
    (write-char #\0 stream)
    (loop repeat depth do (write-char #\} stream))))

(describe "editor nesting limits"
  (it "rejects array nesting above the configured depth via edit-toml"
    (let* ((*toml-max-nesting-depth* 256)
           (text (format nil "value = ~A" (%edit-test-nested-arrays 257)))
           (source (%edit-test-bytes text))
           (condition
             (handler-case
                 (edit-toml source '("value") 0)
               (toml-format-preservation-error (condition) condition))))
      (expect (and condition
                   (string= "TOML nesting depth limit exceeded"
                            (toml-format-preservation-error-message
                             condition))))))
  (it "rejects inline-table nesting above the configured depth via edit-toml"
    (let* ((*toml-max-nesting-depth* 1024)
           (text (format nil "value = ~A"
                         (%edit-test-nested-inline-tables 1025)))
           (source (%edit-test-bytes text))
           (condition
             (handler-case
                 (edit-toml source '("value") 0)
               (toml-format-preservation-error (condition) condition))))
      (expect (and condition
                   (string= "TOML nesting depth limit exceeded"
                            (toml-format-preservation-error-message
                             condition))))))
  (it "edits a value at the hard nesting ceiling under the default control stack"
    (let* ((depth cl-toml-kit::+toml-max-nesting-depth-ceiling+)
           (*toml-max-nesting-depth* (1+ depth))
           (text (format nil "value = ~A"
                         (%edit-test-nested-arrays depth)))
           (source (%edit-test-bytes text))
           (result (edit-toml source '("value") "0")))
      (expect (string= "0" (%edit-test-value result '("value")))))))
