(in-package #:cl-toml-kit)

(defconstant +toml-min-integer+ -9223372036854775808)
(defconstant +toml-max-integer+ 9223372036854775807)

(defun %writer-error-path (path)
  (when path
    (loop for index downfrom (1- (fill-pointer path)) to 0
          collect (aref path index))))

(defun %signal-encoding-error (message value path)
  (let ((*print-length* 10)
        (*print-level* 3))
    (error (make-toml-encoding-error
            :message (format nil "~A (value ~S)" message value)
            :path (reverse (%writer-error-path path))))))

(declaim (ftype function %write-string-value %write-value))

(defmacro %with-writer-path (path key &body body)
  `(progn
    (vector-push-extend ,key ,path)
    (unwind-protect
         (progn ,@body)
      (decf (fill-pointer ,path)))))

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
  (let ((start 0)
        (length (length value)))
    (loop for index from 0 below length
          for character = (char value index)
          for code = (char-code character)
          for escape = (and (< code 128)
                            (aref *toml-basic-string-escape* code))
          do (when (or escape (< code 32) (= code 127))
               (write-string value stream :start start :end index)
               (if escape
                   (write-string escape stream)
                   (progn
                     (write-string "\\u" stream)
                     (loop for shift from 12 downto 0 by 4
                           do (write-char (char "0123456789ABCDEF"
                                                 (ldb (byte 4 shift) code))
                                          stream))))
               (setf start (1+ index))))
    (write-string value stream :start start :end length))
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
                       (%with-writer-path path key
                         (%signal-encoding-error "Table keys must be strings"
                                                 key path)))
                     (unless first (write-string ", " stream))
                     (setf first nil)
                     (%with-writer-path path key
                       (%write-key key stream)
                       (write-string " = " stream)
                       (%write-value value stream path)))
                   table))
        (write-string " }" stream))))

(defun %array-of-tables-p (value)
  (and (plusp (length value))
       (loop for item across value always (hash-table-p item))))

(defun %write-array (value stream path)
  (write-char #\[ stream)
  (loop for index from 0 below (length value)
        do (when (plusp index) (write-string ", " stream))
           (%with-writer-path path index
             (%write-value (aref value index) stream path)))
  (write-char #\] stream))

(define-toml-emitter %write-value (value stream path))

(defun %entry-kind (value)
  (cond ((hash-table-p value) :table)
        ((and (toml-array-p value) (%array-of-tables-p value)) :array-table)
        (t :value)))

(defun %write-key-path (path key stream)
  (loop for index below (fill-pointer path)
        do (%write-key (aref path index) stream)
           (write-char #\. stream))
  (%write-key key stream))

(defun write-table (table reversed-path stream)
  (declare (type (and vector (not simple-array)) reversed-path))
  (unless (toml-table-p table)
    (%signal-encoding-error "Table must use the EQUAL hash-table test"
                            table reversed-path))
  (let ((tables nil)
        (array-tables nil))
    (maphash (lambda (key value)
               (unless (stringp key)
                 (%with-writer-path reversed-path key
                   (%signal-encoding-error "Table keys must be strings"
                                           key reversed-path)))
               (case (%entry-kind value)
                 (:value
                  (%write-key key stream)
                  (write-string " = " stream)
                  (%with-writer-path reversed-path key
                    (%write-value value stream reversed-path))
                  (write-char #\Newline stream))
                 (:table (push (cons key value) tables))
                 (:array-table (push (cons key value) array-tables))))
             table)
    (dolist (entry (nreverse tables))
      (let ((key (car entry))
            (value (cdr entry)))
        (write-char #\[ stream)
        (%write-key-path reversed-path key stream)
        (write-string "]" stream)
        (write-char #\Newline stream)
        (%with-writer-path reversed-path key
          (write-table value reversed-path stream))))
    (dolist (entry (nreverse array-tables))
      (let ((key (car entry))
            (value (cdr entry)))
        (loop for item across value
              do (write-string "[[" stream)
                 (%write-key-path reversed-path key stream)
                 (write-string "]]" stream)
                 (write-char #\Newline stream)
                 (%with-writer-path reversed-path key
                   (write-table item reversed-path stream)))))))

(defun %write-root (value stream)
  (unless (hash-table-p value)
    (%signal-encoding-error "The top-level TOML value must be a hash-table"
                            value nil))
  (write-table value (make-array 8 :adjustable t :fill-pointer 0) stream))

(defun write-toml (value stream)
  "Write VALUE as TOML to STREAM and return VALUE."
  (check-type stream stream)
  (%write-root value stream)
  value)

(defun encode (value)
  "Return VALUE encoded as TOML text."
  (with-output-to-string (stream)
    (write-toml value stream)))
