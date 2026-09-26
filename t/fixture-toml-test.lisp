(in-package #:cl-toml-kit/test)

(defstruct (toml-fixture (:constructor %make-toml-fixture))
  toml
  json)

(defun %fixture-root ()
  (merge-pathnames "t/fixtures/toml-test/"
                   (asdf:system-source-directory "cl-toml-kit")))

(defun %fixture-files (directory type)
    (let ((manifest (merge-pathnames "files-toml-1.1.0.txt" (%fixture-root))))
    (with-open-file (stream manifest)
      (sort (loop for relative = (read-line stream nil)
                  while relative
                  when (and (uiop:string-prefix-p (format nil "~A/" directory)
                                                  relative)
                            (string= type (pathname-type relative)))
                    collect (merge-pathnames relative (%fixture-root)))
            #'string< :key #'namestring))))

(defun %read-file-text (pathname)
  (with-open-file (stream pathname :direction :input)
    (with-output-to-string (out)
      (loop for char = (read-char stream nil nil)
            while char do (write-char char out)))))

(defun %read-json-file (pathname)
  (json-kit:parse (%read-file-text pathname)))

(defun load-toml-fixtures ()
  (let ((valid (mapcar (lambda (toml)
                         (%make-toml-fixture
                          :toml toml
                          :json (make-pathname :type "json" :defaults toml)))
                       (%fixture-files "valid" "toml")))
        (invalid (%fixture-files "invalid" "toml")))
    (list :valid valid :invalid invalid)))

(defun %expected-type-value (expected)
  (values (gethash "type" expected) (gethash "value" expected)))

(defun %float-text= (expected actual)
  (cond
    ((string= expected "nan") (and (floatp actual) (sb-ext:float-nan-p actual)))
    ((string= expected "inf") (= actual sb-ext:double-float-positive-infinity))
    ((string= expected "-inf") (= actual sb-ext:double-float-negative-infinity))
    (t (= actual (let ((*read-default-float-format* 'double-float))
                   (read-from-string expected))))))

(defun %datetime-text= (expected actual)
  (handler-case
      (let ((normalized
              (cl-date-kit:format-offset-date-time
               (cl-date-kit:parse-offset-date-time expected :profile :rfc3339)
               :profile :rfc3339)))
        (and (cl-date-kit:offset-date-time-p actual)
             (string= normalized
                      (cl-date-kit:format-offset-date-time actual :profile :rfc3339))))
    (cl-date-kit:cl-date-kit-error () nil)))

(defun %expected-value= (expected actual)
  (cond
    ((hash-table-p expected)
     (multiple-value-bind (type value) (%expected-type-value expected)
       (if (and (stringp type) (stringp value))
           (cond
         ((string= type "string") (and (stringp actual) (string= value actual)))
         ((string= type "integer") (and (integerp actual) (= (parse-integer value) actual)))
         ((string= type "float") (and (floatp actual) (%float-text= value actual)))
         ((string= type "bool")
          (if (string= value "true")
              (eql actual t)
              (eql actual +toml-false+)))
         ((string= type "datetime")
          (%datetime-text= value actual))
         ((string= type "datetime-local")
          (and (cl-date-kit:local-date-time-p actual)
               (string= value (cl-date-kit:format-local-date-time actual :profile :rfc3339))))
         ((string= type "date-local")
          (and (cl-date-kit:local-date-p actual)
               (string= value (cl-date-kit:format-local-date actual))))
         ((string= type "time-local")
          (and (cl-date-kit:local-time-p actual)
               (string= value (cl-date-kit:format-local-time actual :profile :rfc3339)))))
           (and (hash-table-p actual)
                (= (hash-table-count expected) (hash-table-count actual))
                (loop for key being the hash-keys of expected
                      always (multiple-value-bind (item present) (gethash key actual)
                               (and present
                                    (%expected-value= (gethash key expected) item))))))))
    ((vectorp expected)
     (and (vectorp actual)
          (= (length expected) (length actual))
          (loop for item across expected
                for index from 0
                always (%expected-value= item (aref actual index)))))
    (t nil)))

(defun toml-fixture-valid-p (fixture)
  (%expected-value= (%read-json-file (toml-fixture-json fixture))
                    (parse-file (toml-fixture-toml fixture))))
