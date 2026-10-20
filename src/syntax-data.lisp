;;;; src/syntax-data.lisp
(in-package #:cl-toml-kit)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun %ascii-table (predicate)
    (let ((table (make-array 128 :element-type 'bit :initial-element 0)))
      (dotimes (code 128 table)
        (when (funcall predicate (code-char code))
          (setf (sbit table code) 1))))))

(defmacro define-toml-ascii-table (name character predicate)
  `(defparameter ,name
     (%ascii-table
      (lambda (,character)
        ,predicate))))

(defmacro define-toml-hex-value-table (name)
  (let ((table (gensym "TABLE")))
    `(defparameter ,name
       (let ((,table (make-array 128 :initial-element nil)))
         (dotimes (code 128 ,table)
           (setf (aref ,table code) (digit-char-p (code-char code) 16)))))))

(defmacro define-toml-escape-data (entries hex-widths)
  (let ((letters nil)
        (decoded nil)
        (table (gensym "TABLE"))
        (letters-name '+toml-escape-letters+)
        (values-name '+toml-escape-table+)
        (writer-table-name '*toml-basic-string-escape*))
    (dolist (entry entries)
      (push (first entry) letters)
      (push (second entry) decoded))
    (setf letters (nreverse letters)
          decoded (nreverse decoded))
    `(progn
       (defparameter ,letters-name
         (coerce ',letters 'simple-string))
       (defparameter ,values-name
         (vector ,@decoded))
       (defparameter ,writer-table-name
         (let ((,table (make-array 128 :initial-element nil)))
           (loop for letter across ,letters-name
                 for character across ,values-name
                 unless (char= character #\Escape)
                   do (setf (aref ,table (char-code character)) (concatenate 'string
                                                                             "\\"
                                                                             (string letter))))
           ,table))
       (define-toml-lookup %toml-hex-escape-width ,hex-widths))))

(defmacro define-toml-integer-range (minimum-name minimum maximum-name maximum predicate-name)
  (let ((integer (gensym "INTEGER")))
    `(progn
       (defconstant ,minimum-name
         ,minimum)
       (defconstant ,maximum-name
         ,maximum)
       (defun ,predicate-name (,integer)
         (<= ,minimum-name ,integer ,maximum-name)))))

(defmacro define-toml-byte-sequence (name octets)
  `(defparameter ,name
     (vector ,@octets)))

(defmacro define-toml-character-class (name characters)
  (let ((character (gensym "CHARACTER")))
    `(defun ,name (,character)
       (and (characterp ,character) (member ,character ',characters :test #'char=)))))

(defmacro define-toml-lookup (name entries &key (otherwise nil))
  (let ((lookup-key (gensym "KEY")))
    `(defun ,name (,lookup-key)
       (case ,lookup-key
         ,@(loop for (entry-key value) in entries
                 collect `(,entry-key ,value))
         (otherwise ,otherwise)))))

;; Keep writer call sites compatible with the generic lookup macro.
(defmacro define-toml-error-messages (name entries &key (otherwise nil))
  `(define-toml-lookup ,name ,entries :otherwise ,otherwise))

(define-toml-ascii-table +toml-bare-key-table+
                         char
                         (or (alpha-char-p char)
                             (digit-char-p char)
                             (char= char #\_)
                             (char= char #\-)))

(define-toml-ascii-table +toml-decimal-table+ char (digit-char-p char 10))

(define-toml-ascii-table +toml-space-table+ char (member char '(#\Space #\Tab)))

(define-toml-ascii-table +toml-control-table+ char (< (char-code char) #x20))

(define-toml-hex-value-table +toml-hex-value-table+)

(defun %toml-hex-digit-value (character)
  (let ((code (char-code character)))
    (and (< code 128) (aref +toml-hex-value-table+ code))))

(define-toml-escape-data
 ((#\b #\Backspace) (#\t #\Tab)
  (#\n #\Newline)
  (#\f #\Page)
  (#\r #\Return)
  (#\e #\Escape)
  (#\" #\")
  (#\\ #\\))
 ((#\x 2) (#\u 4) (#\U 8)))

(define-toml-integer-range +toml-min-integer+
                           -9223372036854775808
                           +toml-max-integer+
                           9223372036854775807
                           %toml-integer-in-range-p)

(defparameter +toml-positive-infinity-tokens+
  '("inf" "+inf"))

(defparameter +toml-negative-infinity-token+
  "-inf")

(defparameter +toml-nan-tokens+
  '("nan" "+nan" "-nan"))

(defparameter +toml-nan+
  (let ((zero 0.0d0))
    (sb-int:with-float-traps-masked (:invalid) (/ zero zero))))

(define-toml-byte-sequence +toml-utf8-bom+ (239 187 191))

(defconstant +toml-carriage-return+ #\Return)

(defconstant +toml-double-quote+ #\")
(defconstant +toml-underscore+ #\_)

(defconstant +toml-unicode-scalar-max+
  #x10FFFF)

(defconstant +toml-unicode-surrogate-start+
  #xD800)

(defconstant +toml-unicode-surrogate-end+
  #xDFFF)

(defconstant +toml-line-feed+ #\Newline)

(defparameter +toml-newline-characters+
  (list +toml-carriage-return+ +toml-line-feed+))

(define-toml-ascii-table +toml-value-terminator-table+ char
  (or (member char +toml-newline-characters+ :test #'char=)
      (member char '(#\, #\] #\} #\#) :test #'char=)))

(defconstant +toml-single-quote+ #\')

(defparameter +toml-quote-characters+
  (list +toml-double-quote+ +toml-single-quote+))
