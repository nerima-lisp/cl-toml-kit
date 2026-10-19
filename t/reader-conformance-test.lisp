(in-package #:cl-toml-kit/test)

(defun %register-reader-conformance-tests ()
  (let ((fixtures (load-toml-fixtures)))
    ;; flake.nix pins cl-weave v1.4.0; its it-each macro requires a literal proper list
    ;; of cases (cl-weave/src/registration.lisp:41-70). Fixtures load at runtime, so EVAL
    ;; receives their generated cases for macro expansion.
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
             (let ((condition (handler-case (parse-file pathname)
                                (toml-parse-error (error) error))))
               (expect (typep condition 'toml-parse-error))
               (expect (plusp (toml-parse-error-line condition)))
               (expect (plusp (toml-parse-error-column condition))))))))
