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
  "Register deferred test groups once, then run the full suite with a reproducible property seed."
  (unless *reader-conformance-tests-registered-p*
    (%register-reader-conformance-tests)
    (%register-roundtrip-tests)
    (setf *reader-conformance-tests-registered-p* t))
  (let ((cl-weave:*property-seed*
          (or (let ((environment-seed (uiop:getenv "CL_WEAVE_PROPERTY_SEED")))
                (when environment-seed
                  (parse-integer environment-seed)))
              8675309)))
    (unless (run-all :reporter :spec :timeout-ms 10000)
      (error "cl-toml-kit test suite failed")))
  t)
