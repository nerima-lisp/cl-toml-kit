;;;; t/package.lisp
(defpackage #:cl-toml-kit/test
  (:use #:cl #:cl-toml-kit)
  (:shadowing-import-from #:cl-weave #:describe)
  (:import-from #:cl-weave #:it #:it-each #:it-property #:expect #:signals
                #:run-all #:gen-recursive #:gen-one-of #:gen-map #:gen-integer
                #:gen-string #:gen-member)
  (:export #:run-tests))

(in-package #:cl-toml-kit/test)

(defvar *reader-conformance-tests-registered-p* nil)

(defun run-tests ()
  "Run the foundation data and condition specifications."
  (unless *reader-conformance-tests-registered-p*
    (%register-reader-conformance-tests)
    (setf *reader-conformance-tests-registered-p* t))
  (sb-int:with-float-traps-masked (:invalid :overflow :underflow :divide-by-zero)
    (unless (run-all :reporter :spec :timeout-ms 10000)
      (error "cl-toml-kit test suite failed")))
  t)
