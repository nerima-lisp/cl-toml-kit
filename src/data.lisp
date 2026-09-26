;;;; src/data.lisp
(in-package #:cl-toml-kit)

;;; The table is deliberately data, rather than a second hand-written list of
;;; DEFSTRUCT forms.  Model files can extend it before invoking the macro.
(defparameter *toml-model-table* nil)

(defmacro define-data-model (name slots &key (constructor t) (predicate t)
                                      documentation)
  "Generate a small immutable-by-convention data model from SLOTS.
SLOTS is a list of (NAME INITFORM [TYPE]).  The generated constructor accepts
keyword arguments and the generated predicate is a normal type predicate."
  (let* ((model (string-upcase (symbol-name name)))
         (predicate-name (intern (format nil "~A-P" model) *package*))
         (constructor-name (and constructor
                                (intern (format nil "MAKE-~A" model) *package*)))
         (conc-name (intern (format nil "~A-" model) *package*)))
    `(progn
       (defstruct (,name
                    ,@(when constructor `((:constructor ,constructor-name)))
                    ,@(when predicate `((:predicate ,predicate-name)))
                    (:conc-name ,conc-name))
         ,@(when documentation (list documentation))
         ,@(mapcar (lambda (slot)
                     (destructuring-bind (slot-name &optional initform type) slot
                       `(,slot-name ,initform ,@(when type `(:type ,type)))))
                   slots))
       ',name)))

(defmacro define-toml-model (name slots &key documentation)
  "Register and generate a TOML model described by SLOTS.
This is the public spelling used by model extensions; it is intentionally a
thin declarative layer over DEFINE-DATA-MODEL."
  `(progn
     (pushnew ',name *toml-model-table*)
     (define-data-model ,name ,slots :documentation ,documentation)))
