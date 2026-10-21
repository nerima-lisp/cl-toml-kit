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
            ("value = { answer = 1 other = 2 }"))
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
        (when (probe-file pathname) (delete-file pathname)))))
  (it-each (("a = 1e400" 4 1 5 "representable finite floating-point value" nil)
            ("c = { x = 1 x = 2 }" 12 1 13 "comma or closing brace" nil)
            (#.(format nil "x = 1~%x = 2") 10 2 5 "unique key" ("x"))
            ("a = \"\\q\"" 5 1 6 "valid escape sequence" nil)
            ("[" 1 1 2 "key" nil)
            (#.(format nil "[a]~%[a]") 4 2 1 "unique table" ("a"))
            (#.(format nil "[a]~%  [a]  ") 6 2 3 "unique table" ("a"))
            (#.(format nil "[[a]]~%[a]") 6 2 1 "table" ("a"))
            (#.(format nil "a = 1~%[a]") 6 2 1 "table" ("a"))
            (#.(format nil "[a]~%b = 1~%[a]") 10 3 1 "unique table" ("a"))
            (#.(format nil "[a.b]~%[a]~%[a]") 10 3 1 "unique table" ("a"))
            (#.(format nil "a = {b = 1}~%[a]") 12 2 1 "extendable table" ("a"))
            (#.(format nil "a.b = 1~%[a]") 8 2 1 "unique table" ("a"))
            (#.(format nil "[a]~%x = 1~%[a.x]") 10 3 1 "table" ("a" "x"))
            (#.(format nil "x = 1~%[[x]]") 6 2 1 "array table" ("x"))
            (#.(format nil "[[t]]~%[t.u]~%[t.u]") 12 3 1 "unique table"
             ("t" "u"))
            (#.(format nil "[a]~C~C[a]" (code-char 13) (code-char 10))
             5 2 1 "unique table" ("a"))
            (#.(format nil "bee = \"\"\"~%hee~%gee\\~C ~%" (code-char 9))
             21 4 1 "closing string delimiter" nil))
      "reports golden error slots for ~S"
      (text position line column expected path)
    (let ((condition (%reader-error text)))
      (expect
       (and (typep condition (quote toml-parse-error))
            (equal (list position line column expected path)
                   (list (toml-parse-error-position condition)
                         (toml-parse-error-line condition)
                         (toml-parse-error-column condition)
                         (toml-parse-error-expected condition)
                         (toml-parse-error-path condition)))))))
  (it "keeps absolute position and bounded text for character-limit errors"
    (let* ((*toml-max-input-characters* 64)
           (condition
             (handler-case
                 (parse (make-string 4096 :initial-element (aref "x" 0)))
               (toml-parse-error (condition) condition))))
      (expect (typep condition 'toml-parse-error))
      (expect (= 64 (toml-parse-error-position condition)))
      (expect (<= (length (toml-parse-error-text condition)) 40))))
  (it "omits unavailable coordinates from character-limit reports"
    (let* ((*toml-max-input-characters* 64)
           (condition
             (handler-case
                 (parse (make-string 4096 :initial-element (aref "x" 0)))
               (toml-parse-error (condition) condition)))
           (report (princ-to-string condition)))
      (expect (equal (list nil nil)
                     (list (toml-parse-error-line condition)
                           (toml-parse-error-column condition))))
      (expect (search "at position 64" report))
      (expect (not (search "null" report))))))
(describe "TOML reader input types"
  (it "reports the datum and allowed types for a numeric source"
    (let ((condition
            (handler-case (progn (parse 42) nil)
              (type-error (error) error))))
      (expect
       (and (typep condition (quote type-error))
            (= 42 (type-error-datum condition))
            (equal (list (quote or) (quote string) (quote stream))
                   (type-error-expected-type condition)))))))
