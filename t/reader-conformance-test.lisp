(in-package #:cl-toml-kit/test)

(defun %register-reader-conformance-tests ()
  (let ((fixtures (load-toml-fixtures)))
    ;; cl-weave v1.3.0 requires literal it-each cases, so runtime fixtures use EVAL.
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
    ;; cl-weave v1.3.0 requires literal it-each cases, so runtime fixtures use EVAL.
    (eval `(it-each
             ,(mapcar (lambda (pathname) (list (namestring pathname) pathname))
                      (getf fixtures :invalid))
             "rejects invalid TOML fixture ~A"
             (name pathname)
             (declare (ignore name))
             (let ((condition (handler-case (parse-file pathname)
                                (toml-parse-error (error) error))))
               (expect (typep condition 'toml-parse-error))
               (expect (plusp (toml-parse-error-line condition)))
               (expect (plusp (toml-parse-error-column condition))))))))
