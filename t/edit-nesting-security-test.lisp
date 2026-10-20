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
  (it "edits an array leaf at the exact hard nesting ceiling"
    (let* ((depth cl-toml-kit::+toml-max-nesting-depth-ceiling+)
           (*toml-max-nesting-depth* depth)
           (*toml-max-path-components* (1+ depth))
           (path (cons "value" (make-list depth :initial-element 0)))
           (text (format nil "value = ~A" (%edit-test-nested-arrays depth)))
           (source (%edit-test-bytes text))
           (result (edit-toml source path 7)))
      (expect (= (1+ depth) (length path)))
      (expect (= 7 (%edit-test-value result path)))))
  (it "edits an inline-table leaf at the exact hard nesting ceiling"
    (let* ((depth cl-toml-kit::+toml-max-nesting-depth-ceiling+)
           (*toml-max-nesting-depth* depth)
           (*toml-max-path-components* (1+ depth))
           (path (cons "value" (make-list depth :initial-element "a")))
           (text (format nil "value = ~A"
                         (%edit-test-nested-inline-tables depth)))
           (source (%edit-test-bytes text))
           (result (edit-toml source path 7)))
      (expect (= (1+ depth) (length path)))
      (expect (= 7 (%edit-test-value result path)))))
  (it "rejects deeply nested new values without a storage condition"
    (let* ((source (%edit-test-bytes "value = 0"))
           (value (let ((nested 0))
                    (dotimes (index 100000 nested)
                      (declare (ignore index))
                      (setf nested (vector nested)))))
           (condition
             (handler-case
                 (progn (edit-toml source "value" value) nil)
               (storage-condition (condition) condition)
               (toml-kit-error (condition) condition)
               (error (condition) condition))))
      (expect (and (typep condition (quote toml-kit-error))
                   (typep condition (quote toml-encoding-error))
                   (not (typep condition (quote storage-condition)))))
      (expect (zerop (length (delete-toml source "value")))))))
