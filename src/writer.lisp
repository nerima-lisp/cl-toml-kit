(in-package #:cl-toml-kit)

(defconstant +toml-min-integer+ -9223372036854775808)
(defconstant +toml-max-integer+ 9223372036854775807)

(defun %signal-encoding-error (message value path)
  (let ((*print-length* 10)
        (*print-level* 3))
    (error (make-toml-encoding-error
            :message (format nil "~A (value ~S)" message value)
            :path (reverse path)))))

(declaim (ftype function %write-string-value %write-value))

(defun %write-key (key stream)
  (if (and (plusp (length key))
           (loop for character across key
                 always (and (< (char-code character) 128)
                             (= 1 (aref *toml-bare-key-character-p*
                                        (char-code character))))))
      (write-string key stream)
      (%write-string-value key stream)))

(defun %write-string-value (value stream)
  (write-char #\" stream)
  (loop for character across value
        for code = (char-code character)
        do (cond ((and (< code 128)
                       (aref *toml-basic-string-escape* code))
                   (write-string (aref *toml-basic-string-escape* code)
                                 stream))
                  ((or (< code 32) (= code 127))
                   (format stream "\\u~4,'0X" code))
                  (t (write-char character stream))))
  (write-char #\" stream))

(defun %write-integer-value (value stream path)
  (if (<= +toml-min-integer+ value +toml-max-integer+)
      (princ value stream)
      (%signal-encoding-error "Integer is outside TOML's signed 64-bit range"
                              value path)))

(defun %write-float-value (value stream)
  (cond ((sb-ext:float-nan-p value) (write-string "nan" stream))
        ((sb-ext:float-infinity-p value)
         (write-string (if (minusp value) "-inf" "inf") stream))
        (t (let ((*read-default-float-format* 'double-float))
             (prin1 value stream)))))

(defun %write-inline-table (table stream path)
  (unless (toml-table-p table)
    (%signal-encoding-error "Table must use the EQUAL hash-table test"
                            table path))
  (if (zerop (hash-table-count table))
      (write-string "{}" stream)
      (progn
        (write-string "{ " stream)
        (let ((first t))
          (maphash (lambda (key value)
                     (unless (stringp key)
                       (%signal-encoding-error "Table keys must be strings"
                                               key (cons key path)))
                     (unless first (write-string ", " stream))
                     (setf first nil)
                     (%write-key key stream)
                     (write-string " = " stream)
                     (%write-value value stream (cons key path)))
                   table))
        (write-string " }" stream))))

(defun %array-of-tables-p (value)
  (and (plusp (length value))
       (loop for item across value always (hash-table-p item))))

(defun %write-array (value stream path)
  (write-char #\[ stream)
  (loop for index from 0 below (length value)
        do (when (plusp index) (write-string ", " stream))
           (%write-value (aref value index) stream (cons index path)))
  (write-char #\] stream))

(define-toml-emitter %write-value (value stream path))

(defun %entry-kind (value)
  (cond ((hash-table-p value) :table)
        ((and (vectorp value) (%array-of-tables-p value)) :array-table)
        (t :value)))

(defun %write-key-path (path key stream)
  (when path
    (%write-key-path (cdr path) (car path) stream)
    (write-char #\. stream))
  (%write-key key stream))

(defun write-table (table reversed-path stream)
  (unless (toml-table-p table)
    (%signal-encoding-error "Table must use the EQUAL hash-table test"
                            table reversed-path))
  (maphash (lambda (key value)
             (unless (stringp key)
               (%signal-encoding-error "Table keys must be strings"
                                       key (cons key reversed-path)))
             (when (eq :value (%entry-kind value))
               (%write-key key stream)
               (write-string " = " stream)
               (%write-value value stream (cons key reversed-path))
               (write-char #\Newline stream)))
           table)
  (maphash (lambda (key value)
             (unless (stringp key)
               (%signal-encoding-error "Table keys must be strings"
                                       key (cons key reversed-path)))
             (when (eq :table (%entry-kind value))
               (write-char #\[ stream)
               (%write-key-path reversed-path key stream)
               (write-string "]" stream)
               (write-char #\Newline stream)
               (write-table value (cons key reversed-path) stream)))
           table)
  (maphash (lambda (key value)
             (unless (stringp key)
               (%signal-encoding-error "Table keys must be strings"
                                       key (cons key reversed-path)))
             (when (eq :array-table (%entry-kind value))
               (loop for item across value
                     do (write-string "[[" stream)
                        (%write-key-path reversed-path key stream)
                        (write-string "]]" stream)
                        (write-char #\Newline stream)
                        (write-table item (cons key reversed-path) stream))))
           table))

(defun %write-root (value stream)
  (unless (hash-table-p value)
    (%signal-encoding-error "The top-level TOML value must be a hash-table"
                            value nil))
  (write-table value nil stream))

(defun write-toml (value stream)
  "Write VALUE as TOML to STREAM and return VALUE."
  (check-type stream stream)
  (%write-root value stream)
  value)

(defun encode (value)
  "Return VALUE encoded as TOML text."
  (with-output-to-string (stream)
    (write-toml value stream)))
