(in-package #:cl-toml-kit/test)

(defun %reader-test-nested-arrays (depth)
  (with-output-to-string (stream)
    (loop repeat depth
          do (write-char #\[ stream))
    (write-char #\0 stream)
    (loop repeat depth
          do (write-char #\] stream))))

(defun %reader-test-nested-inline-tables (depth)
  (with-output-to-string (stream)
    (loop repeat depth
          do (write-string "{a = " stream))
    (write-char #\0 stream)
    (loop repeat depth
          do (write-char #\} stream))))

(defun %reader-test-nesting-error (text &optional source-name)
  (handler-case (progn
                  (parse text :source-name source-name)
                  nil)
    (toml-parse-error (condition)
      condition)))

(defun %reader-test-nesting-result (thunk)
  (handler-case (progn
                  (funcall thunk)
                  :returned)
    (toml-parse-error ()
      :toml-parse-error)
    (cl-toml-kit::toml-kit-error ()
      :toml-kit-error)
    (storage-condition (condition)
      (type-of condition))
    (serious-condition (condition)
      (type-of condition))))

(describe "reader nesting limits"
          (it "accepts arrays at depth 1024 and rejects depth 1025"
              (let* ((*toml-max-nesting-depth* 1024)
                     (valid
                      (parse
                       (format nil
                               "value = ~A"
                               (%reader-test-nested-arrays 1024))))
                     (source
                      (format nil
                              "value = ~A"
                              (%reader-test-nested-arrays 1025)))
                     (condition (%reader-test-nesting-error source))
                     (expected-position (+ (length "value = ") 1024))
                     (expected-message
                      (nth-value 1 (cl-toml-kit::%toml-limit :nesting-depth))))
                (expect (hash-table-p valid))
                (expect
                 (and (typep condition 'toml-parse-error)
                      (= expected-position
                         (toml-parse-error-position condition))
                      (string= expected-message
                               (toml-parse-error-expected condition))))))
          (it "accepts inline tables at depth 1024 and rejects depth 1025"
              (let* ((*toml-max-nesting-depth* 1024)
                     (valid
                      (parse
                       (format nil
                               "value = ~A"
                               (%reader-test-nested-inline-tables 1024))))
                     (source
                      (format nil
                              "value = ~A"
                              (%reader-test-nested-inline-tables 1025)))
                     (condition (%reader-test-nesting-error source))
                     (expected-position (+ (length "value = ") (* 5 1024)))
                     (expected-message
                      (nth-value 1 (cl-toml-kit::%toml-limit :nesting-depth))))
                (expect (hash-table-p valid))
                (expect
                 (and (typep condition 'toml-parse-error)
                      (= expected-position
                         (toml-parse-error-position condition))
                      (string= expected-message
                               (toml-parse-error-expected condition))))))
          (it "rejects 100000-level arrays and inline tables through parse"
              (let* ((*toml-max-nesting-depth* 1024)
                     (array-result
                      (%reader-test-nesting-result
                       (lambda ()
                         (parse
                          (format nil
                                  "value = ~A"
                                  (%reader-test-nested-arrays 100000))))))
                     (inline-result
                      (%reader-test-nesting-result
                       (lambda ()
                         (parse
                          (format nil
                                  "value = ~A"
                                  (%reader-test-nested-inline-tables 100000)))))))
                (expect (eq :toml-parse-error array-result))
                (expect (eq :toml-parse-error inline-result))))
          (it "rejects 100000-level arrays and inline tables through edit-toml"
              (let* ((*toml-max-nesting-depth* 1024)
                     (array-source
                      (%edit-test-bytes
                       (format nil
                               "value = ~A"
                               (%reader-test-nested-arrays 100000))))
                     (inline-source
                      (%edit-test-bytes
                       (format nil
                               "value = ~A"
                               (%reader-test-nested-inline-tables 100000))))
                     (array-result
                      (%reader-test-nesting-result
                       (lambda ()
                         (edit-toml array-source '("value") 0))))
                     (inline-result
                      (%reader-test-nesting-result
                       (lambda () (edit-toml inline-source '("value") 0)))))
                (expect
                 (eq :toml-format-preservation-error array-result))
                (expect
                 (eq :toml-format-preservation-error inline-result))))
          (it "normalizes source names on nesting-limit errors"
              (let* ((*toml-max-nesting-depth* 1)
                     (pathname #p"reader-nesting-security.toml")
                     (expected-message
                       (nth-value 1 (cl-toml-kit::%toml-limit :nesting-depth)))
                     (text (format nil "value = ~A" (%reader-test-nested-arrays 2)))
                     (pathname-condition
                       (%reader-test-nesting-error text pathname))
                     (controls
                       (coerce (list (code-char 0)
                                     (code-char #x1B)
                                     (code-char #x80)
                                     (code-char #x9F)
                                     (code-char #x7F))
                               'string))
                     (source-name
                       (concatenate 'string "nesting-" controls
                                    (make-string 300 :initial-element #\x)))
                     (escaped-condition
                       (%reader-test-nesting-error text source-name))
                     (escaped-source-name
                       (and (typep escaped-condition 'toml-parse-error)
                            (toml-parse-error-source-name escaped-condition)))
                     (escape-sequence "\\u0000\\u001B\\u0080\\u009F\\u007F")
                     (escaped-expected
                       (and (typep escaped-condition 'toml-parse-error)
                            (toml-parse-error-expected escaped-condition)))
                     (escape-sequence-present
                       (and (stringp escaped-source-name)
                            (search escape-sequence escaped-source-name)))
                     (source-name-within-limit
                       (and (stringp escaped-source-name)
                            (<= (length escaped-source-name)
                                cl-toml-kit::+toml-diagnostic-limit+)))
                     (source-name-has-no-c0-controls
                       (and (stringp escaped-source-name)
                            (notany (lambda (character)
                                      (< (char-code character) 32))
                                    escaped-source-name)))
                     (source-name-has-no-c1-controls
                       (and (stringp escaped-source-name)
                            (notany (lambda (character)
                                      (<= #x7F (char-code character) #x9F))
                                    escaped-source-name))))
                (expect
                 (equal (list 'toml-parse-error
                              (namestring pathname)
                              expected-message)
                        (list (type-of pathname-condition)
                              (and (typep pathname-condition 'toml-parse-error)
                                   (toml-parse-error-source-name pathname-condition))
                              (and (typep pathname-condition 'toml-parse-error)
                                   (toml-parse-error-expected pathname-condition)))))
                (expect (typep escaped-condition 'toml-parse-error))
                (expect (stringp escaped-source-name))
                (expect (equal expected-message escaped-expected))
                (expect escape-sequence-present)
                (expect source-name-within-limit)
                (expect source-name-has-no-c0-controls)
                (expect source-name-has-no-c1-controls)))


)
