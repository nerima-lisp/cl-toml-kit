(in-package #:cl-toml-kit/test)

(defun %register-roundtrip-tests ()
  (let ((fixtures (getf (load-toml-fixtures) :valid)))
    ;; it-each requires literal cases at macro expansion, so runtime fixtures use EVAL.
    (eval `(it-each
             ,(mapcar (lambda (fixture)
                        (list (namestring (toml-fixture-toml fixture)))) fixtures)
             "round-trips valid TOML fixture ~A"
             (name)
             (let* ((first (parse-file (pathname name)))
                    (second (parse (encode first))))
               (expect (toml-test-value= first second)))))))
