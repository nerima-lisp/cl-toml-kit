(in-package #:cl-toml-kit/test)

(defun %register-reader-conformance-tests ()
  (let ((fixtures (load-toml-fixtures)))
    (eval `(it-each
             ,(mapcar (lambda (fixture)
                        (list (namestring (toml-fixture-toml fixture))))
                      (getf fixtures :valid))
             "reads valid TOML fixture ~A"
             (name)
             (expect (toml-fixture-valid-p
                      (%make-toml-fixture
                       :toml (pathname name)
                       :json (make-pathname :type "json" :defaults (pathname name)))))))
    (eval `(it-each
             ,(mapcar (lambda (pathname) (list (namestring pathname) pathname))
                      (getf fixtures :invalid))
             "rejects invalid TOML fixture ~A"
             (name pathname)
             (declare (ignore name))
             (expect (signals toml-parse-error (parse-file pathname)))))))
