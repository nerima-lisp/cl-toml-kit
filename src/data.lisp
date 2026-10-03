;;;; src/data.lisp
;;;; Native TOML values and the declarative value dispatch table.
(in-package #:cl-toml-kit)

(defstruct (toml-false-sentinel
            (:constructor make-toml-false-sentinel ())
            (:copier nil)
            (:predicate nil)))

(defmethod print-object ((value toml-false-sentinel) stream)
  (print-unreadable-object (value stream :type t :identity nil)))

(sb-ext:define-load-time-global +toml-false+ (make-toml-false-sentinel)
  "The opaque value used for TOML false.")

(defun toml-false-p (value)
  (eq value +toml-false+))

(defconstant +toml-default-max-depth+ 512
  "The default maximum nesting depth for TOML aggregates.")

(defun %toml-max-depth (max-depth)
  (unless (or (null max-depth)
              (and (integerp max-depth) (plusp max-depth)))
    (error ":MAX-DEPTH must be NIL or a positive integer, got ~S."
           max-depth))
  max-depth)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun %toml-ascii-table (predicate)
    (let ((table (make-array 128 :element-type 'bit :initial-element 0)))
      (dotimes (code 128 table)
        (when (funcall predicate (code-char code))
          (setf (sbit table code) 1))))))

(defparameter +toml-bare-key-table+
  (%toml-ascii-table (lambda (char) (or (alpha-char-p char) (digit-char-p char)
                                        (char= char #\_) (char= char #\-)))))

(defparameter +toml-escape-table+
  #(#\Backspace #\Tab #\Newline #\Page #\Return #\Escape #\" #\\)
  "Values for b, t, n, f, r, e, quote, and backslash escapes.")

(defparameter +toml-escape-letters+
  (coerce '(#\b #\t #\n #\f #\r #\e #\" #\\) 'simple-string)
  "The escape letters corresponding to +TOML-ESCAPE-TABLE+.")

(defvar *toml-encoding-path* nil
  "The path used by shared value-dispatch errors while encoding.")

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defparameter *toml-value-specifications*
    '((:table hash-table toml-table)
      (:array simple-vector toml-array)
      (:string string nil)
      (:integer (signed-byte 64) toml-integer)
      (:float double-float toml-float)
      (:true (eql t) nil)
      (:false toml-false-sentinel nil)
      (:offset-date-time cl-date-kit:offset-date-time nil)
      (:local-date-time cl-date-kit:local-date-time nil)
      (:local-date cl-date-kit:local-date nil)
      (:local-time cl-date-kit:local-time nil))))

(defmacro define-toml-value-model ()
  (let ((specifications *toml-value-specifications*))
    (labels ((find-specification (kind)
               (or (find kind specifications :key #'first)
                   (error 'toml-value-model-error
                          :message (format nil "Unknown TOML value kind ~S." kind))))
             (predicate-form (kind value)
               (case kind
                 (:table `(and (hash-table-p ,value)
                               (eq (hash-table-test ,value) 'equal)))
                 (:true `(eq ,value t))
                 (:false `(toml-false-p ,value))
                 (otherwise
                  `(typep ,value ',(second (find-specification kind))))))
             (kind-typecase-clause (specification)
               (destructuring-bind (kind type alias) specification
                 (declare (ignore alias))
                 `(,type (when ,(predicate-form kind 'object) ,kind)))))
      `(progn
         ,@(loop for (kind type alias) in specifications
                 when alias
                   collect `(deftype ,alias () ',type))
         (deftype toml-value ()
           '(or ,@(mapcar (lambda (item) (second item)) specifications)))
         (defun toml-table-p (value)
           ,(predicate-form :table 'value))
         (defun toml-array-p (value)
           ,(predicate-form :array 'value))
         (defun toml-integer-p (value)
           ,(predicate-form :integer 'value))
         (defun toml-float-p (value)
           ,(predicate-form :float 'value))
         (defun toml-value-kind (value)
           (let ((object value))
             (typecase object
               ,@(mapcar #'kind-typecase-clause specifications)
               (otherwise nil))))
         (defun toml-value-p (value)
           (not (null (toml-value-kind value))))))))

(define-toml-value-model)

(defmacro toml-value-typecase (value &body clauses)
  "Dispatch VALUE by the native TOML value model.

Clause keys are TOML kind keywords.  Unknown keys are rejected at macro
expansion time."
  (let ((known-kinds (mapcar #'first *toml-value-specifications*))
        (object (gensym "VALUE"))
        (forms-by-kind (make-hash-table :test #'eq))
        (otherwise-forms nil))
    (dolist (clause clauses)
      (destructuring-bind (key &body forms) clause
        (if (eq key t)
            (setf otherwise-forms forms)
            (progn
              (unless (member key known-kinds)
                (error 'toml-value-model-error
                       :message (format nil "Unknown TOML value kind ~S." key)))
              (setf (gethash key forms-by-kind) forms)))))
    `(let ((,object ,value))
       (typecase ,object
         ,@(loop for (kind type alias) in *toml-value-specifications*
                 for forms = (gethash kind forms-by-kind)
                 when forms
                   collect `(,type
                             ,(if (eq kind :table)
                                  `(if (toml-table-p ,object)
                                       (progn ,@forms)
                                       (error (make-toml-encoding-error
                                               :message "Invalid TOML table"
                                               :path *toml-encoding-path*)))
                                  `(progn ,@forms))))
         (otherwise ,@(or otherwise-forms
                           '((error (make-toml-encoding-error
                                     :message "Not a TOML value"
                                     :path *toml-encoding-path*)))))))))
