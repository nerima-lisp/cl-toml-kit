(in-package #:cl-toml-kit/test)

(defun %reader-error (text)
  (handler-case (progn (parse text) nil)
    (toml-parse-error (condition) condition)))

(describe "TOML reader errors"
  (it-each (("value = 9223372036854775808")
            ("value = -9223372036854775809")
            ("value = 01")
            ("value = 1__0")
            ("value = 0x")
            ("value = 0b102")
            ("value = [1 2]")
            ("value = { answer = 1, }"))
      "reports invalid TOML input ~S with source coordinates"
      (text)
    (let ((condition (%reader-error text)))
      (expect (typep condition 'toml-parse-error))
      (expect (plusp (toml-parse-error-line condition)))
      (expect (plusp (toml-parse-error-column condition)))))
  (it-each (("value = 1e309")
            ("value = 1e-324")
            ("value = 07:32.5"))
      "rejects invalid numeric or time value ~S"
      (text)
    (expect (signals toml-parse-error (parse text))))
  (it-each ((#.(concatenate 'string "a = 1" (string #\Return)) 1 6 5)
            (#.(concatenate 'string "a = " (string (code-char 1))) 1 5 4)
            ("t/fixtures/toml-test/invalid/encoding/bad-utf8-at-end.toml" 5 11 241))
      "reports a concrete position for malformed input ~S"
      (input expected-line expected-column expected-position)
    (let ((condition (handler-case
                         (if (search ".toml" input)
                             (parse-file input)
                             (parse input))
                       (toml-parse-error (error) error))))
      (expect (and (typep condition 'toml-parse-error)
                   (= expected-position (toml-parse-error-position condition))))
      (expect (= expected-line (toml-parse-error-line condition)))
      (expect (= expected-column (toml-parse-error-column condition)))))
  (it-each ((#.(format nil "a = 1~%b = 2~%c = 3~%a = 4"))
            (#.(format nil "[a]~%x = 1~%[a]~%y = 2"))
            (#.(format nil "[[items]]~%x = 1~%[[items]]~%x = 2~%[items]~%y = 3"))
            ("x = { a = 1, a = 2 }"))
      "reports duplicate definitions in ~S with source coordinates"
      (text)
    (let ((condition (%reader-error text)))
      (expect (typep condition 'toml-parse-error))
      (expect (plusp (toml-parse-error-line condition)))
      (expect (plusp (toml-parse-error-column condition)))))
  (it-each (("[") ("[[items]") ("[items]]"))
      "rejects malformed table header ~S"
      (text)
    (expect (signals toml-parse-error (parse text))))
  (it-each (("value = \"\\uD800\"")
            ("value = \"\\U00110000\""))
      "rejects invalid Unicode scalar escape ~S"
      (text)
    (expect (signals toml-parse-error (parse text))))
  (it "maps known expected keys and rejects unknown expected keys"
    (let ((condition
            (handler-case
                (cl-toml-kit::%error-at
                 (cl-toml-kit::%make-reader-state :source "x" :length 1)
                 0 :float-digit)
              (toml-parse-error (error) error))))
      (expect (string= "float digit" (toml-parse-error-expected condition)))
      (expect (signals error
                (cl-toml-kit::%error-at
                 (cl-toml-kit::%make-reader-state :source "x" :length 1)
                 0 :unknown-error-key)))))
  (it "includes a readable source name and diagnostic text"
    (let ((condition (handler-case
                        (parse "a = @" :source-name "example.toml")
                      (toml-parse-error (error) error))))
      (expect (string= "example.toml"
                       (toml-parse-error-source-name condition)))
      (expect (plusp (length (toml-parse-error-text condition))))
      (expect (search "line" (princ-to-string condition)))))
  (it-each ((#(195 169 32 255) 3 1 3)
            (#(239 187 191 195 169 32 255) 6 1 3)
            (#(35 32 195 169 13 10 118 97 108 117 101 32 61 32 255)
             14 2 9))
      "reports matching coordinates for parse-file and edit-toml errors"
      (bytes expected-position expected-line expected-column)
    (let* ((pathname (merge-pathnames "cl-toml-kit-reader-invalid-coordinate.toml"
                                      (uiop:temporary-directory)))
           (octets (make-array (length bytes)
                               :element-type (quote (unsigned-byte 8))
                               :initial-contents bytes)))
      (unwind-protect
           (progn
             (%reader-write-bytes pathname octets)
             (let* ((file-condition
                      (handler-case (progn (parse-file pathname) nil)
                        (toml-parse-error (condition) condition)))
                    (edit-condition
                      (handler-case
                          (progn (edit-toml octets (list "value") "new") nil)
                        (toml-parse-error (condition) condition)))
                    (file-coordinates
                      (when (typep file-condition (quote toml-parse-error))
                        (list (toml-parse-error-position file-condition)
                              (toml-parse-error-line file-condition)
                              (toml-parse-error-column file-condition))))
                    (edit-coordinates
                      (when (typep edit-condition (quote toml-parse-error))
                        (list (toml-parse-error-position edit-condition)
                              (toml-parse-error-line edit-condition)
                              (toml-parse-error-column edit-condition)))))
               (expect (and file-coordinates edit-coordinates))
               (expect (equal (list expected-position expected-line expected-column)
                              file-coordinates))
               (expect (equal file-coordinates edit-coordinates))))
        (when (probe-file pathname) (delete-file pathname))))))
