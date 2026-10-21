(in-package #:cl-toml-kit/test)

(defun %reader-write-bytes (pathname bytes)
  (with-open-file (stream pathname :direction :output :if-exists :supersede
                          :element-type '(unsigned-byte 8))
    (write-sequence bytes stream)))

(describe "TOML file reader"
  (it-each (("bmp-utf8"
             #(109 101 115 115 97 103 101 32 61 32 34 240 159 140 159 34 10)
             "🌟")
            ("invalid-utf8" #(97 32 61 32 34 192 175 34 10) :error))
      "reads file case ~A"
      (case-name bytes expected)
    (let ((pathname
            (merge-pathnames
             (format nil "cl-toml-kit-reader-~A.toml" case-name)
             (uiop:temporary-directory))))
      (unwind-protect
           (progn
             (%reader-write-bytes pathname bytes)
             (if (eq expected :error)
                 (expect (signals toml-parse-error (parse-file pathname)))
                 (expect (toml-test-value=
                          expected
                          (gethash "message" (parse-file pathname))))))
         (when (probe-file pathname)
           (delete-file pathname)))))
  (it "reads a UTF-8 BOM through parse-file and edit-toml"
    (let* ((pathname (merge-pathnames "cl-toml-kit-reader-bom.toml"
                                      (uiop:temporary-directory)))
           (source (concatenate (quote (vector (unsigned-byte 8)))
                                #(239 187 191)
                                #(110 97 109 101 32 61 32 34 111 108 100 34 10)))
           (edited (edit-toml source (list "name") "old")))
      (unwind-protect
           (progn
             (%reader-write-bytes pathname source)
             (expect (string= "old" (gethash "name" (parse-file pathname))))
             (expect
               (string= "old"
                        (gethash "name"
                                 (parse
                                  (cl-codec-kit:octets-to-string
                                   edited :encoding :utf-8 :start 3))))))
        (when (probe-file pathname) (delete-file pathname)))))
  (it-each (("cr-lf" #(97 32 61 32 49 13 255 10) 6 2 1)
            ("cr-followed-by-text" #(97 32 61 32 49 13 88 255) 7 2 2))
      "reports invalid UTF-8 coordinates after CR case ~A"
      (case-name bytes expected-position expected-line expected-column)
    (let ((pathname
            (merge-pathnames
             (format nil "cl-toml-kit-reader-invalid-~A.toml" case-name)
             (uiop:temporary-directory))))
      (unwind-protect
           (progn
             (%reader-write-bytes pathname bytes)
             (let ((condition
                     (handler-case (progn (parse-file pathname) nil)
                       (toml-parse-error (error) error))))
               (expect
                (and (typep condition (quote toml-parse-error))
                     (equal (list expected-position expected-line expected-column)
                            (list (toml-parse-error-position condition)
                                  (toml-parse-error-line condition)
                                  (toml-parse-error-column condition)))))))
        (when (probe-file pathname) (delete-file pathname))))))