(in-package #:cl-toml-kit)

;;;; This table is the single source for writer value dispatch.  The macro
;;;; below turns the declarative entries into a typecase-like cond.
(defparameter *toml-writer-value-specifications*
  '((:table hash-table)
    (:array vector)
    (:string string)
    (:integer integer)
    (:float double-float)
    (:true (eql t))
    (:false toml-false-sentinel)
    (:offset-date-time cl-date-kit:offset-date-time)
    (:local-date-time cl-date-kit:local-date-time)
    (:local-date cl-date-kit:local-date)
    (:local-time cl-date-kit:local-time)))

(defparameter *toml-bare-key-character-p*
  (let ((table (make-array 128 :element-type 'bit :initial-element 0)))
    (loop for code from (char-code #\A) to (char-code #\Z)
          do (setf (aref table code) 1))
    (loop for code from (char-code #\a) to (char-code #\z)
          do (setf (aref table code) 1))
    (loop for code from (char-code #\0) to (char-code #\9)
          do (setf (aref table code) 1))
    (setf (aref table (char-code #\-)) 1
          (aref table (char-code #\_)) 1)
    table))

(defmacro define-toml-emitter (name (value stream path) &body clauses)
  `(defun ,name (,value ,stream ,path)
     (cond
       ,@(mapcar (lambda (clause)
                   (destructuring-bind (tag type &body body) clause
                     (declare (ignore tag))
                     `((typep ,value ',type) ,@body)))
                 clauses)
       (t (%signal-encoding-error "Unsupported TOML value" ,value ,path)))))
