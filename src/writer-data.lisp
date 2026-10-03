(in-package #:cl-toml-kit)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defparameter *toml-writer-emitter-specifications*
  '((:table (%write-inline-table value stream path))
    (:array (%write-array value stream path))
    (:string (%write-string-value value stream))
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

(defparameter *toml-bare-key-character-p* +toml-bare-key-table+)

(defparameter *toml-basic-string-escape*
  (let ((table (make-array 128 :initial-element nil)))
    (loop for index below (length +toml-escape-table+)
          for character = (aref +toml-escape-table+ index)
          for letter = (aref +toml-escape-letters+ index)
          do (setf (aref table (char-code character))
                   (format nil "\\~C" letter)))
    table))

(defstruct (toml-writer-state (:constructor %make-writer-state))
  stream
  (path (make-array 8 :adjustable t :fill-pointer 0))
  (depth 0 :type fixnum)
  (max-depth +toml-default-max-depth+ :type (or null integer)))

(defvar *toml-writer-state* nil)
