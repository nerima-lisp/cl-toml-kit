;;;; src/data.lisp
;;;; Native TOML values and the declarative value dispatch table.
(in-package #:cl-toml-kit)

(defstruct (toml-false-sentinel
            (:constructor make-toml-false-sentinel ())
            (:copier nil)
            (:predicate nil)))

(defparameter +toml-false+ (make-toml-false-sentinel)
  "The opaque value used for TOML false.")

(deftype toml-table () 'hash-table)
(deftype toml-array () 'simple-vector)
(deftype toml-integer () '(signed-byte 64))
(deftype toml-float () 'double-float)
(deftype toml-value () t)

(defparameter *toml-value-specifications*
  '((:table hash-table)
    (:array simple-vector)
    (:string string)
    (:integer (signed-byte 64))
    (:float double-float)
    (:true (eql t))
    (:false toml-false-sentinel)
    (:offset-date-time cl-date-kit:offset-date-time)
    (:local-date-time cl-date-kit:local-date-time)
    (:local-date cl-date-kit:local-date)
    (:local-time cl-date-kit:local-time)))

(defun toml-false-p (value)
  (eq value +toml-false+))

(defun toml-table-p (value)
  (and (hash-table-p value)
       (eq (hash-table-test value) 'equal)
       (block valid
         (maphash (lambda (key ignored)
                   (declare (ignore ignored))
                   (unless (stringp key) (return-from valid nil)))
                 value)
         t)))

(defun toml-array-p (value)
  (simple-vector-p value))

(defun toml-integer-p (value)
  (typep value '(signed-byte 64)))

(defun toml-float-p (value)
  (typep value 'double-float))

(defun toml-value-p (value)
  (or (toml-table-p value)
      (toml-array-p value)
      (stringp value)
      (toml-integer-p value)
      (toml-float-p value)
      (eq value t)
      (toml-false-p value)
      (cl-date-kit:offset-date-time-p value)
      (cl-date-kit:local-date-time-p value)
      (cl-date-kit:local-date-p value)
      (cl-date-kit:local-time-p value)))

(defmacro toml-value-typecase (value &body clauses)
  "Dispatch VALUE by the native TOML value model."
  (let ((object (gensym "VALUE")))
    `(let ((,object ,value))
       (typecase ,object
         (hash-table
          (if (toml-table-p ,object)
              (toml-value-typecase-dispatch ,object ,clauses)
              (error 'toml-encoding-error :message "Invalid TOML table")))
         (simple-vector (toml-value-typecase-dispatch ,object ,clauses))
         (string (toml-value-typecase-dispatch ,object ,clauses))
         (integer (toml-value-typecase-dispatch ,object ,clauses))
         (double-float (toml-value-typecase-dispatch ,object ,clauses))
         (t (toml-value-typecase-dispatch ,object ,clauses))))))

(defmacro toml-value-typecase-dispatch (value clauses)
  `(case (toml-value-kind ,value)
     ,@(mapcar (lambda (clause)
                 (destructuring-bind (key &body forms) clause
                   (if (eq key t)
                       `(t ,@forms)
                       `(,key ,@forms))))
               clauses)
     (otherwise (error 'toml-encoding-error :message "Not a TOML value"))))

(defun toml-value-kind (value)
  (cond ((toml-table-p value) :table)
        ((toml-array-p value) :array)
        ((stringp value) :string)
        ((toml-integer-p value) :integer)
        ((toml-float-p value) :float)
        ((eq value t) :true)
        ((toml-false-p value) :false)
        ((cl-date-kit:offset-date-time-p value) :offset-date-time)
        ((cl-date-kit:local-date-time-p value) :local-date-time)
        ((cl-date-kit:local-date-p value) :local-date)
        ((cl-date-kit:local-time-p value) :local-time)))
