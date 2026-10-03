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
    (%register-roundtrip-tests)
    (setf *reader-conformance-tests-registered-p* t))
  (let* ((record-assertion (find-symbol "RECORD-ASSERTION" "CL-WEAVE"))
         (original-record-assertion (symbol-function record-assertion))
         (assertion-count 0)
         (test-count (length (cl-weave:list-tests
                              :reporter :sexp
                              :stream (make-broadcast-stream)))))
    (setf (symbol-function record-assertion)
          (lambda (&rest arguments)
            (incf assertion-count)
            (apply original-record-assertion arguments)))
    (unwind-protect
         (progn
           (unless (run-all :reporter :spec :timeout-ms 10000)
             (error "cl-toml-kit test suite failed"))
           (format t "~&Test cases: ~D~%Assertions: ~D~%"
                   test-count assertion-count)
           t)
      (setf (symbol-function record-assertion) original-record-assertion))))
