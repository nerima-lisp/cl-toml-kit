;;;; src/reader-data.lisp
(in-package #:cl-toml-kit)

(defstruct (toml-reader-state (:constructor %make-reader-state))
  (source "" :type simple-string)
  source-name
  (position 0 :type fixnum)
  (line 1 :type fixnum)
  (column 1 :type fixnum)
  (length 0 :type fixnum)
  (depth 0 :type fixnum)
  (max-depth +toml-default-max-depth+ :type (or null integer))
  (path nil)
  (root nil)
  (current nil)
  (table-states (make-hash-table :test #'eq))
  (array-tables (make-hash-table :test #'eq))
  (buffer (make-array 64 :element-type 'character :adjustable t :fill-pointer 0)))

(defparameter +toml-decimal-table+
  (%toml-ascii-table (lambda (char) (digit-char-p char 10))))
(defparameter +toml-space-table+
  (%toml-ascii-table (lambda (char) (member char '(#\Space #\Tab)))))
(defparameter +toml-control-table+
  (%toml-ascii-table (lambda (char) (< (char-code char) #x20))))
