;;;; benchmark/cases.lisp
;;;; Generated inputs are built once, outside the measured thunks.
(in-package #:cl-toml-kit/benchmark)

(defparameter *benchmark-sizes* '(256 512 1024))

(defun %reader-input (size)
  (with-output-to-string (stream)
    (dotimes (index size)
      (format stream "key~D = ~D~%" index index))))

(defun %writer-input (size)
  (let ((table (make-hash-table :test 'equal)))
    (dotimes (index size table)
      (setf (gethash (format nil "key~D" index) table)
            (if (evenp index)
                index
                (format nil "value-~D" index))))))

(defun %run-reader (source)
  (unless (fboundp 'cl-toml-kit:parse)
    (error 'benchmark-pending
           :reason "cl-toml-kit:parse is not available yet"))
  (funcall (symbol-function 'cl-toml-kit:parse) source))

(defun %run-write-toml (value)
  (cl-toml-kit:write-toml value (make-broadcast-stream)))

(defun %register-cases ()
  (setf *benchmarks* nil)
  (dolist (size *benchmark-sizes*)
    (let ((source (%reader-input size))
          (value (%writer-input size)))
      (define-benchmark (format nil "reader/parse/~D" size)
        (:operation :reader-parse :input-size size
         :upper-seconds 30d0 :upper-bytes (* 256 1024 1024))
        (%run-reader source))
      (define-benchmark (format nil "writer/encode/~D" size)
        (:operation :writer-encode :input-size size
         :upper-seconds 30d0 :upper-bytes (* 256 1024 1024))
        (cl-toml-kit:encode value))
      (define-benchmark (format nil "writer/write-toml/~D" size)
        (:operation :writer-write-toml :input-size size
         :upper-seconds 30d0 :upper-bytes (* 256 1024 1024))
        (%run-write-toml value)))))

(eval-when (:load-toplevel :execute)
  (%register-cases))
