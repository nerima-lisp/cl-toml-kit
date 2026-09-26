;;;; benchmark/runner.lisp
;;;; Load-safe benchmark declarations. Execution is explicit and diagnostic.
(defpackage #:cl-toml-kit/benchmark
  (:use #:cl)
  (:export #:define-benchmark #:run-benchmarks))

(in-package #:cl-toml-kit/benchmark)

(defstruct benchmark name operation thunk)
(defparameter *benchmarks* nil)

(defmacro define-benchmark (name (&key operation) &body body)
  `(push (make-benchmark :name ,name :operation ,operation
                         :thunk (lambda () ,@body))
         *benchmarks*))

(defun run-benchmarks ()
  (dolist (benchmark (nreverse *benchmarks*))
    (let ((started (get-internal-real-time)))
      (funcall (benchmark-thunk benchmark))
      (format t "~A~C~A~C~,6F~%"
              (benchmark-name benchmark) #\Tab
              (benchmark-operation benchmark) #\Tab
              (/ (- (get-internal-real-time) started)
                 (float internal-time-units-per-second 1d0)))))
  t)
