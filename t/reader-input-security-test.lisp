(in-package #:cl-toml-kit/test)

(defun %reader-input-error (thunk)
  (handler-case
      (progn (funcall thunk) nil)
    (toml-parse-error (condition) condition)))

(defun %reader-input-surrogate-source (context)
  (let ((surrogate (string (code-char #xd800))))
    (ecase context
      (:basic-string
       (concatenate 'string "value = \"" surrogate "\""))
      (:literal-string
       (concatenate 'string "value = '" surrogate "'"))
      (:multiline-basic-string
       (concatenate 'string "value = \"\"\"" surrogate "\"\"\""))
      (:multiline-literal-string
       (concatenate 'string "value = '''" surrogate "'''"))
      (:quoted-key
       (concatenate 'string "\"" surrogate "\" = 1"))
      (:comment
       (concatenate 'string "# " surrogate)))))

(defun %reader-input-write-bytes (pathname bytes)
  (with-open-file (stream pathname :direction :output :if-exists :supersede
                          :element-type '(unsigned-byte 8))
    (write-sequence bytes stream)))

(describe "reader input security"
  (it-each ((:basic-string)
            (:literal-string)
            (:multiline-basic-string)
            (:multiline-literal-string)
            (:quoted-key)
            (:comment))
      "rejects a raw surrogate in ~A input"
      (context)
    (let ((condition
            (%reader-input-error
             (lambda ()
               (parse (%reader-input-surrogate-source context))))))
      (expect (typep condition 'toml-parse-error))
      (expect (string= "Unicode scalar value"
                       (toml-parse-error-expected condition)))))
  (it "checks the string character limit before parsing invalid TOML"
    (let* ((text "value = [")
           (*toml-max-input-characters* (1- (length text)))
           (condition
             (%reader-input-error (lambda () (parse text)))))
      (expect (typep condition 'toml-parse-error))
      (expect (string= "TOML input character limit exceeded"
                       (toml-parse-error-expected condition)))))
  (it "stops a character stream after reading limit plus one"
    (with-input-from-string (stream "value = [ trailing text")
      (let* ((*toml-max-input-characters* 4)
             (condition
               (%reader-input-error (lambda () (parse stream)))))
        (expect (string= "TOML input character limit exceeded"
                         (toml-parse-error-expected condition)))
        (expect (= 5 (file-position stream))))))
  (it "checks the file byte limit before decoding invalid UTF-8"
    (let* ((pathname
             (merge-pathnames "cl-toml-kit-reader-byte-limit.toml"
                              (uiop:temporary-directory)))
           (bytes (make-array 4 :element-type '(unsigned-byte 8)
                              :initial-element #xff))
           (*toml-max-input-bytes* 3)
           (condition nil))
      (unwind-protect
           (progn
             (%reader-input-write-bytes pathname bytes)
             (setf condition
                   (%reader-input-error
                    (lambda () (parse-file pathname))))
             (expect (typep condition 'toml-parse-error))
             (expect
               (and (= 0 (toml-parse-error-position condition))
                    (string= (namestring pathname)
                             (toml-parse-error-source-name condition))))
             (expect (string= "TOML input byte limit exceeded"
                              (toml-parse-error-expected condition))))
        (when (probe-file pathname)
          (delete-file pathname)))))
  (it "checks decoded file characters before parsing invalid TOML"
    (let* ((pathname
             (merge-pathnames "cl-toml-kit-reader-char-limit.toml"
                              (uiop:temporary-directory)))
           (text "value = [")
           (bytes (map '(vector (unsigned-byte 8)) #'char-code text))
           (*toml-max-input-bytes* (length bytes))
           (*toml-max-input-characters* (1- (length text)))
           (condition nil))
      (unwind-protect
           (progn
             (%reader-input-write-bytes pathname bytes)
             (setf condition
                   (%reader-input-error
                    (lambda () (parse-file pathname))))
             (expect (typep condition 'toml-parse-error))
             (expect (string= "TOML input character limit exceeded"
                              (toml-parse-error-expected condition)))
             (expect (= (1- (length text))
                        (toml-parse-error-position condition))))
        (when (probe-file pathname)
          (delete-file pathname))))))
