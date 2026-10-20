(in-package #:cl-toml-kit)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defparameter *toml-writer-emitter-specifications*
    '((:table (%write-inline-table value stream path))
      (:array (%write-array value stream path))
      (:string (%write-string-value value stream path))
      (:integer (%write-integer-value value stream path))
      (:float (%write-float-value value stream))
      (:true (write-string "true" stream))
      (:false (write-string "false" stream))
      (:offset-date-time
       (write-string (cl-date-kit:format-offset-date-time
                      value :profile :rfc3339) stream))
      (:local-date-time
       (write-string (cl-date-kit:format-local-date-time
                      value :profile :rfc3339) stream))
      (:local-date
       (write-string (cl-date-kit:format-local-date value) stream))
      (:local-time
       (write-string (cl-date-kit:format-local-time
                      value :profile :rfc3339) stream)))))

(define-toml-lookup %toml-writer-error-message
  ((:table-equal-hash "Table must use the EQUAL hash-table test")
   (:key "Table keys must be strings")))
