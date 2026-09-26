(in-package #:cl-toml-kit)

(defconstant +toml-min-integer+ -9223372036854775808)
(defconstant +toml-max-integer+ 9223372036854775807)

(defun %signal-encoding-error (message value path)
  (declare (ignore value))
  (error (make-toml-encoding-error :message message :path path)))

(defun %valid-table-p (table)
  (and (hash-table-p table)
       (eq (hash-table-test table) 'equal)))

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
        do (case character
             (#\Backspace (write-string "\\b" stream))
             (#\Tab (write-string "\\t" stream))
             (#\Newline (write-string "\\n" stream))
             (#\Return (write-string "\\r" stream))
             (#\Page (write-string "\\f" stream))
             (#\" (write-string "\\\"" stream))
             (#\\ (write-string "\\\\" stream))
             (otherwise
              (if (< (char-code character) 32)
                  (format stream "\\u~4,'0X" (char-code character))
                  (write-char character stream)))))
  (write-char #\" stream))

(defun %float-string (value)
  (cond ((sb-ext:float-nan-p value) "nan")
        ((sb-ext:float-infinity-p value)
         (if (minusp value) "-inf" "inf"))
        (t
         (let ((text (prin1-to-string value)))
           (setf text (substitute #\e #\d text))
           (unless (or (find #\. text) (find #\e text))
             (setf text (concatenate 'string text ".0")))
           text))))

(defun %write-date-value (value stream)
  (write-string
   (cond ((cl-date-kit:offset-date-time-p value)
          (cl-date-kit:format-offset-date-time value))
         ((cl-date-kit:local-date-time-p value)
          (cl-date-kit:format-local-date-time value))
         ((cl-date-kit:local-date-p value)
          (cl-date-kit:format-local-date value))
         (t (cl-date-kit:format-local-time value)))
   stream))

(define-toml-emitter %write-scalar-value (value stream path)
  (:string string (%write-string-value value stream))
  (:integer integer
    (if (<= +toml-min-integer+ value +toml-max-integer+)
        (princ value stream)
        (%signal-encoding-error "Integer is outside TOML's signed 64-bit range"
                                value path)))
  (:float double-float (write-string (%float-string value) stream))
  (:true (eql t) (write-string "true" stream))
  (:false toml-false-sentinel (write-string "false" stream))
  (:offset-date-time cl-date-kit:offset-date-time
    (%write-date-value value stream))
  (:local-date-time cl-date-kit:local-date-time
    (%write-date-value value stream))
  (:local-date cl-date-kit:local-date (%write-date-value value stream))
  (:local-time cl-date-kit:local-time (%write-date-value value stream)))

(defun %write-inline-table (table stream path)
  (unless (%valid-table-p table)
    (%signal-encoding-error "Table must use the EQUAL hash-table test" table path))
  (write-string "{ " stream)
  (let ((first t))
    (maphash (lambda (key value)
               (unless (stringp key)
                 (%signal-encoding-error "Table keys must be strings" key
                                         (append path (list key))))
               (unless first (write-string ", " stream))
               (setf first nil)
               (%write-key key stream)
               (write-string " = " stream)
               (%write-value value stream (append path (list key))))
             table))
  (write-string " }" stream))

(defun %array-of-tables-p (value)
  (and (plusp (length value))
       (loop for item across value always (hash-table-p item))))

(defun %write-array (value stream path)
  (write-char #\[ stream)
  (loop for index from 0 below (length value)
        do (when (plusp index) (write-string ", " stream))
           (%write-value (aref value index) stream (append path (list index))))
  (write-char #\] stream))

(defun %write-value (value stream path)
  (cond ((hash-table-p value) (%write-inline-table value stream path))
        ((stringp value) (%write-string-value value stream))
        ((vectorp value) (%write-array value stream path))
        (t (%write-scalar-value value stream path))))

(defun %entry-kind (value)
  (cond ((and (hash-table-p value) (%valid-table-p value)
              (plusp (hash-table-count value))) :table)
        ((and (vectorp value) (%array-of-tables-p value)) :array-table)
        (t :value)))

(defun %collect-entries (table path continuation)
  (let ((entries nil))
    (maphash (lambda (key value)
               (unless (stringp key)
                 (%signal-encoding-error "Table keys must be strings" key
                                         (append path (list key))))
               (push (list key value (%entry-kind value)) entries))
             table)
    (funcall continuation (nreverse entries))))

(defun %write-table-content (table stream path)
  (unless (%valid-table-p table)
    (%signal-encoding-error "Table must use the EQUAL hash-table test" table path))
  (flet ((continue-writing (entries)
           (dolist (entry entries)
             (when (eq :value (third entry))
               (%write-key (first entry) stream)
               (write-string " = " stream)
               (%write-value (second entry) stream
                             (append path (list (first entry))))
               (write-char #\Newline stream)))
           (dolist (entry entries)
             (case (third entry)
               (:table
                (write-char #\[ stream)
                (%write-key-path path (first entry) stream)
                (write-string "]" stream)
                (write-char #\Newline stream)
                (%write-table-content (second entry) stream
                                      (append path (list (first entry)))))
               (:array-table
                (loop for item across (second entry)
                      do (write-string "[[" stream)
                         (%write-key-path path (first entry) stream)
                         (write-string "]]" stream)
                         (write-char #\Newline stream)
                         (%write-table-content item stream
                                               (append path
                                                       (list (first entry))))))))))
    (declare (dynamic-extent #'continue-writing))
    (%collect-entries table path #'continue-writing)))

(defun %write-key-path (path key stream)
  (loop for component in (append path (list key))
        for first = t then nil
        do (unless first (write-char #\. stream))
           (%write-key component stream)))

(defun %write-root (value stream)
  (unless (hash-table-p value)
    (%signal-encoding-error "The top-level TOML value must be a hash-table"
                            value nil))
  (%write-table-content value stream nil))

(defun write-toml (value stream)
  "Write VALUE as TOML to STREAM.

The traversal is linear in the number of emitted values, apart from the
implementation-defined hash-table traversal cost."
  (check-type stream stream)
  (%write-root value stream)
  value)

(defun encode (value)
  "Return VALUE encoded as TOML text.

This allocates a string proportional to the encoded output size."
  (with-output-to-string (stream)
    (write-toml value stream)))
