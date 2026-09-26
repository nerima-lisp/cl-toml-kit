(in-package #:cl-toml-kit)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defparameter *toml-writer-emitter-specifications*
  '((:string (%write-string-value value stream))
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

(defparameter *toml-bare-key-character-p*
  (let ((table (make-array 128 :element-type 'bit :initial-element 0)))
    (loop for code from (char-code #\A) to (char-code #\Z)
          do (setf (aref table code) 1))
    (loop for code from (char-code #\a) to (char-code #\z)
          do (setf (aref table code) 1))
    (loop for code from (char-code #\0) to (char-code #\9)
          do (setf (aref table code) 1))
    (setf (aref table (char-code #\-)) 1
          (aref table (char-code #\_)) 1)
    table))

(defparameter *toml-basic-string-escape*
  (let ((table (make-array 128 :initial-element nil)))
    (setf (aref table (char-code #\Backspace)) "\\b"
          (aref table (char-code #\Tab)) "\\t"
          (aref table (char-code #\Newline)) "\\n"
          (aref table (char-code #\Page)) "\\f"
          (aref table (char-code #\Return)) "\\r"
          (aref table (char-code #\")) "\\\""
          (aref table (char-code #\\)) "\\\\")
    table))
