(in-package #:cl-toml-kit/test)

(defun %reader-write-bytes (pathname bytes)
  (with-open-file (stream pathname :direction :output :if-exists :supersede
                          :element-type '(unsigned-byte 8))
    (write-sequence bytes stream)))

(describe "TOML file reader"
  (it "reads UTF-8 files including characters outside the BMP"
    (let ((pathname (merge-pathnames "cl-toml-kit-reader-utf8.toml"
                                     (uiop:temporary-directory))))
      (unwind-protect
           (progn
             (%reader-write-bytes pathname
                                  #(109 101 115 115 97 103 101 32 61 32
                                    34 240 159 140 159 34 10))
             (expect (string= "🌟" (gethash "message" (parse-file pathname)))))
        (when (probe-file pathname) (delete-file pathname)))))
  (it "reports invalid UTF-8 as a TOML parse error"
    (let ((pathname (merge-pathnames "cl-toml-kit-reader-invalid.toml"
                                     (uiop:temporary-directory))))
      (unwind-protect
           (progn
             (%reader-write-bytes pathname #(97 32 61 32 34 192 175 34 10))
             (expect (signals toml-parse-error (parse-file pathname))))
        (when (probe-file pathname) (delete-file pathname))))))
