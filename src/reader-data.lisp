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
  (buffer (make-array 64 :element-type 'character :adjustable t :fill-pointer 0)))
(progn
  (define-toml-character-class %toml-value-terminator-p
    (#\Return #\Newline #\, #\] #\} #\#))
  (define-toml-character-class %toml-date-time-separator-p
    (#\T #\t #\Space))
  (define-toml-character-class %toml-date-time-offset-marker-p
    (#\z #\Z #\+ #\-))
  (define-toml-character-class %toml-exponent-marker-p
    (#\e #\E))
  (define-toml-character-class %toml-numeric-sign-p (#\+ #\-))
  (define-toml-character-map %toml-date-separator-kind
    ((#\- :date) (#\: :time) (#\. :fraction)))
  (define-toml-integer-radices %toml-integer-base
    ((#\x 16) (#\o 8) (#\b 2)))
  (define-toml-error-messages %toml-reader-error-message
    ((:digit-between-underscores "digit between underscores")
     (:exponent-digit "exponent digit")
     (:float-digit "float digit")
     (:integer-digit "integer digit")
     (:no-leading-zero "no leading zero")
     (:representable-finite-float
      "representable finite floating-point value")
     (:unicode-scalar-value "Unicode scalar value")
     (:defined-table "defined table")
     (:table "table")
     (:inline-table "inline table")
     (:array-table "array table")
     (:line-end "line ending"))))
