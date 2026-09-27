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

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun %ascii-table (predicate)
    (let ((table (make-array 128 :element-type 'bit :initial-element 0)))
      (dotimes (code 128 table)
        (when (funcall predicate (code-char code))
          (setf (sbit table code) 1))))))

(defparameter +toml-bare-key-table+
  (%ascii-table (lambda (char) (or (alpha-char-p char) (digit-char-p char)
                                   (char= char #\_) (char= char #\-)))))
(defparameter +toml-decimal-table+
  (%ascii-table (lambda (char) (digit-char-p char 10))))
(defparameter +toml-hex-table+
  (%ascii-table (lambda (char) (digit-char-p char 16))))
(defparameter +toml-space-table+
  (%ascii-table (lambda (char) (member char '(#\Space #\Tab)))))
(defparameter +toml-control-table+
  (%ascii-table (lambda (char) (< (char-code char) #x20))))

(defparameter +toml-escape-table+
  #(#\Backspace #\Tab #\Newline #\Page #\Return #\Escape #\" #\\)
  "Values for b, t, n, f, r, e, quote, and backslash escapes.")
(defparameter +toml-escape-letters+
  (coerce '(#\b #\t #\n #\f #\r #\e #\" #\\) 'simple-string)
  "The escape letters corresponding to +TOML-ESCAPE-TABLE+.")
