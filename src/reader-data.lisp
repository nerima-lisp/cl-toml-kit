;;;; src/reader-data.lisp
(in-package #:cl-toml-kit)

(defstruct (toml-reader-state (:constructor %make-reader-state))
  (source "" :type simple-string)
  source-name
  (position 0 :type fixnum)
  (length 0 :type fixnum)
  (root nil)
  (current nil)
  (table-states (make-hash-table :test #'eq))
  (buffer
   (make-array 64 :element-type 'character :adjustable t :fill-pointer 0)))

(define-toml-character-class %toml-date-time-separator-p (#\T #\t #\Space))

(define-toml-character-class %toml-date-time-offset-marker-p (#\z #\Z #\+ #\-))

(define-toml-character-class %toml-exponent-marker-p (#\e #\E))

(define-toml-character-class %toml-numeric-sign-p (#\+ #\-))

(define-toml-lookup %toml-date-separator-kind
  ((#\- :date) (#\: :time) (#\. :fraction)))

(define-toml-lookup %toml-integer-base ((#\x 16) (#\o 8) (#\b 2)))

(define-toml-lookup %toml-reader-error-message
  ((:array-table "array table")
   (:closing-array-table-delimiter "]]")
   (:closing-bracket "]")
   (:closing-string-delimiter "closing string delimiter")
   (:comma-or-closing-bracket "comma or closing bracket")
   (:comma-or-closing-brace "comma or closing brace")
   (:defined-table "defined table")
   (:digit-between-underscores "digit between underscores")
   (:equals "=")
   (:exponent-digit "exponent digit")
   (:extendable-table "extendable table")
   (:float-digit "float digit")
   (:fraction-digit "fraction digit")
   (:hex-digit "hex digit")
   (:inline-table "inline table")
   (:integer-digit "integer digit")
   (:key "key")
   (:lf-after-cr "LF after CR")
   (:line-end "line ending")
   (:literal-string-character "literal string character")
   (:multiline-string-delimiter "multiline string delimiter")
   (:no-leading-zero "no leading zero")
   (:printable-character "printable character")
   (:printable-string-character "printable string character")
   (:representable-finite-float "representable finite floating-point value")
   (:signed-64-bit-integer "signed 64-bit integer")
   (:single-line-key "single-line key")
   (:single-line-string "single-line string")
   (:table "table")
   (:unique-inline-key "unique inline key")
   (:unique-key "unique key")
   (:unique-table "unique table")
   (:unicode-scalar-value "Unicode scalar value")
   (:unsigned-prefixed-integer "unsigned prefixed integer")
   (:valid-date-or-time "valid date or time")
   (:valid-escape-sequence "valid escape sequence"))
  :otherwise (error "Unknown TOML reader error key"))
