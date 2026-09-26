;;;; src/package.lisp
(defpackage #:cl-toml-kit
  (:use #:cl)
  (:export
   ;; Reader / writer protocol
   #:parse #:encode
   ;; Conditions
   #:toml-kit-error #:toml-parse-error #:toml-parse-error-source-name
   #:toml-parse-error-position
   #:toml-parse-error-line #:toml-parse-error-column
   #:toml-parse-error-path #:toml-parse-error-expected
   #:toml-parse-error-context #:toml-parse-error-text
   #:toml-encoding-error #:toml-encoding-error-message
   #:toml-encoding-error-path
   ;; Declarative model support
   #:define-data-model #:define-toml-model #:*toml-model-table*
   ;; Core values
   #:toml-document #:toml-document-p #:make-toml-document
   #:toml-document-entries
   #:toml-table #:toml-table-p #:make-toml-table #:toml-table-entries
   #:toml-array #:toml-array-p #:make-toml-array #:toml-array-elements
   #:toml-value-p #:toml-key-p
   #:toml-value-kind #:toml-value-kind-p
   #:toml-get #:toml-set #:toml-table-get #:toml-table-set
   #:toml-array-push
   #:make-string-value #:string-value-p #:string-value
   #:make-integer-value #:integer-value-p #:integer-value
   #:make-float-value #:float-value-p #:float-value
   #:make-boolean-value #:boolean-value-p #:boolean-value
   #:make-array-value #:make-table-value #:array-elements #:table-entries
   #:table-value
   ;; Date/time value protocol
   #:toml-date-time-p #:toml-date-p #:toml-time-p #:toml-offset-date-time-p
   #:toml-offset-time-p #:toml-zoned-date-time-p))
