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

(defmacro define-toml-escape-data (entries)
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
                   do (setf (aref ,table (char-code character))
                            (concatenate 'string "\\" (string letter))))
           ,table)))))

(defmacro define-toml-integer-range (minimum-name minimum
                                        maximum-name maximum)
  `(progn
     (defconstant ,minimum-name ,minimum)
     (defconstant ,maximum-name ,maximum)))

(defmacro define-toml-float-data (&key positive-infinity-tokens
                                       negative-infinity-token
                                       nan-tokens
                                       nan-value)
  `(progn
     (defparameter +toml-positive-infinity-tokens+
       ',positive-infinity-tokens)
     (defparameter +toml-negative-infinity-token+
       ,negative-infinity-token)
     (defparameter +toml-nan-tokens+
       ',nan-tokens)
     (defparameter +toml-nan+
       ,nan-value)))

(defmacro define-toml-byte-sequence (name octets)
  `(defparameter ,name
     (vector ,@octets)))

(define-toml-ascii-table +toml-bare-key-table+ char
                         (or (alpha-char-p char)
                             (digit-char-p char)
                             (char= char #\_)
                             (char= char #\-)))

(define-toml-ascii-table +toml-decimal-table+ char
                         (digit-char-p char 10))

(define-toml-ascii-table +toml-space-table+ char
                         (member char '(#\Space #\Tab)))

(define-toml-ascii-table +toml-control-table+ char
                         (< (char-code char) #x20))

(define-toml-hex-value-table +toml-hex-value-table+)

(defun %toml-hex-digit-value (character)
  (let ((code (char-code character)))
    (and (< code 128) (aref +toml-hex-value-table+ code))))

(define-toml-escape-data
 ((#\b #\Backspace) (#\t #\Tab) (#\n #\Newline) (#\f #\Page)
  (#\r #\Return) (#\e #\Escape) (#\" #\") (#\\ #\\)))

(define-toml-integer-range +toml-min-integer+ -9223372036854775808 +toml-max-integer+ 9223372036854775807)

(define-toml-float-data :positive-infinity-tokens
                        ("inf" "+inf")
                        :negative-infinity-token
                        "-inf"
                        :nan-tokens
                        ("nan" "+nan" "-nan")
                        :nan-value
                        (let ((zero 0.0d0))
                          (sb-int:with-float-traps-masked (:invalid)
                                                          (/ zero zero))))

(define-toml-byte-sequence +toml-utf8-bom+ (239 187 191))
