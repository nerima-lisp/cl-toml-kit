;;;; src/reader-data.lisp
(in-package #:cl-toml-kit)

(defstruct (toml-reader-state (:constructor %make-reader-state))
  (source "" :type simple-string)
  source-name
  (position 0 :type fixnum)
  (line 1 :type fixnum)
  (column 1 :type fixnum)
  (length 0 :type fixnum)
  (root nil)
  (current nil)
  (table-states (make-hash-table :test #'eq))
  (array-tables (make-hash-table :test #'eq))
  (buffer (make-array 64 :element-type 'character :adjustable t :fill-pointer 0)))
