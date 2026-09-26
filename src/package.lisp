;;;; src/package.lisp
(defpackage #:cl-toml-kit
  (:use #:cl)
  (:import-from #:cl-date-kit
                #:offset-date-time #:offset-date-time-p
                #:local-date-time #:local-date-time-p
                #:local-date #:local-date-p
                #:local-time #:local-time-p)
  (:export
   ;; Reader / writer protocol
   #:parse #:parse-file #:encode #:write-toml
   ;; Native values. Table keys are validated by the writer, not predicates.
   #:+toml-false+ #:toml-false-p #:toml-value #:toml-value-p
   #:toml-value-kind #:toml-value-typecase
   #:toml-table #:toml-table-p #:toml-array #:toml-array-p
   #:toml-integer #:toml-integer-p #:toml-float #:toml-float-p
   ;; Conditions
   #:toml-kit-error #:toml-parse-error #:toml-parse-error-source-name
   #:toml-parse-error-position
   #:toml-parse-error-line #:toml-parse-error-column
   #:toml-parse-error-path #:toml-parse-error-expected
   #:toml-parse-error-context #:toml-parse-error-text
   #:toml-encoding-error #:toml-encoding-error-message
   #:toml-encoding-error-path
   ))
