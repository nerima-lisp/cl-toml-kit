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

(describe "editor path validation boundaries"
  (it "rejects a string path when the component limit is zero"
    (let* ((*toml-max-path-components* 0)
           (source (%edit-test-bytes "name = 1~%"))
           (snapshot (copy-seq source))
           (condition
             (handler-case
                 (edit-toml source "name" 2)
               (toml-format-preservation-error (condition) condition))))
      (expect (and condition
                   (string= "TOML path component limit exceeded"
                            (toml-format-preservation-error-message condition))))
      (expect (equalp snapshot source))))
  (it "rejects a vector path longer than the component limit"
    (let* ((*toml-max-path-components* 1)
           (source (%edit-test-bytes "settings = { count = 1 }~%"))
           (snapshot (copy-seq source))
           (condition
             (handler-case
                 (edit-toml source (vector "settings" "count") 2)
               (toml-format-preservation-error (condition) condition))))
      (expect (and condition
                   (string= "TOML path component limit exceeded"
                            (toml-format-preservation-error-message condition))))
      (expect (equalp snapshot source))))
  (it "rejects non-string and non-integer path components"
    (let* ((source (%edit-test-bytes "name = 1~%"))
           (snapshot (copy-seq source))
           (condition
             (handler-case
                 (edit-toml source (list (make-symbol "name")) 2)
               (toml-format-preservation-error (condition) condition))))
      (expect (and condition
                   (string= "Path components must be strings or non-negative integers"
                            (toml-format-preservation-error-message condition))))
      (expect (equalp snapshot source))))
  (it-each ((nil "Path must not be empty")
            (42 "Path must be a string, list, or vector"))
      "rejects invalid path shape ~S with a format-preservation error"
      (path expected-message)
    (let* ((source (%edit-test-bytes "name = 1~%"))
           (snapshot (copy-seq source))
           (condition
             (handler-case
                 (edit-toml source path 2)
               (toml-format-preservation-error (error) error))))
      (expect (and (typep condition (quote toml-format-preservation-error))
                   (string= expected-message
                            (toml-format-preservation-error-message condition))))
      (expect (equalp snapshot source)))))

(describe "editor source type boundaries"
  (it "rejects a non-vector source with the octet-vector type contract"
    (let ((condition
            (handler-case
                (progn (edit-toml 42 (quote ("name")) 2) nil)
              (type-error (condition) condition))))
      (expect (typep condition (quote type-error)))
      (expect (eql 42 (type-error-datum condition)))
      (expect (equal (quote (vector (unsigned-byte 8)))
                     (type-error-expected-type condition))))))
