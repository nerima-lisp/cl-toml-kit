(in-package #:cl-toml-kit)

(defun %writer-error-path (path)
  (when path
    (loop for index from 0 below (fill-pointer path)
          collect (aref path index))))

(defun %signal-encoding-error (message value path)
  (let ((category (cond ((null value) "null")
                        ((stringp value) "string")
                        ((integerp value) "integer")
                        ((hash-table-p value) "table")
                        ((vectorp value) "array")
                        ((characterp value) "character")
                        ((symbolp value) "symbol")
                        ((floatp value) "float")
                        ((consp value) "list")
                        (t "value"))))
    (error (make-toml-encoding-error
            :message (format nil "~A (value ~A)" message category)
            :path (%writer-error-path path)))))

(defun %validate-writer-table (table path)
  (unless (toml-table-p table)
    (%signal-encoding-error (%toml-writer-error-message :table-equal-hash)
                            table path)))

(declaim (ftype function %write-string-value %write-value))

(defvar *toml-writer-active-containers* nil)
(defvar *toml-writer-nesting-depth* nil)
(defvar *toml-writer-nesting-limit* nil)
(defvar *toml-writer-nesting-message* nil)

(defmacro %with-writer-path (path key &body body)
  `(progn
     (vector-push-extend ,key ,path)
     (unwind-protect
         (progn ,@body)
       (decf (fill-pointer ,path)))))

(defmacro %with-writer-context (&optional (initial-depth 0) &body body)
  `(if *toml-writer-active-containers*
       (progn ,@body)
     (multiple-value-bind (limit message)
         (%toml-limit :nesting-depth)
       (let ((*toml-writer-active-containers* (make-hash-table :test #'eq))
             (*toml-writer-nesting-depth* ,initial-depth)
             (*toml-writer-nesting-limit* limit)
             (*toml-writer-nesting-message* message))
         ,@body))))

(defmacro %with-writer-container (container path nested-p &body body)
  (let ((object (gensym "CONTAINER-"))
        (count-depth-p (gensym "COUNT-DEPTH-P")))
    `(%with-writer-context 0
       (let ((,object ,container)
             (,count-depth-p ,nested-p))
         (when (gethash ,object *toml-writer-active-containers*)
           (error (make-toml-encoding-error
                   :message "Cyclic TOML value"
                   :path (%writer-error-path ,path))))
         (when (and ,count-depth-p
                    (>= *toml-writer-nesting-depth*
                        *toml-writer-nesting-limit*))
           (error (make-toml-encoding-error
                   :message *toml-writer-nesting-message*
                   :path (%writer-error-path ,path))))
         (setf (gethash ,object *toml-writer-active-containers*) t)
         (when ,count-depth-p
           (incf *toml-writer-nesting-depth*))
         (unwind-protect
              (progn ,@body)
           (when ,count-depth-p
             (decf *toml-writer-nesting-depth*))
           (remhash ,object *toml-writer-active-containers*))))))

(defun %validate-toml-string (value path)
  (when (loop for character across value
              thereis (<= #xd800 (char-code character) #xdfff))
    (error (make-toml-encoding-error
            :message "String contains a surrogate code point"
            :path (%writer-error-path path)))))

(declaim (inline %validate-writer-key))

(defun %validate-writer-key (key path)
  (%with-writer-path path key
    (unless (stringp key)
      (%signal-encoding-error (%toml-writer-error-message :key) key path))
    (%validate-toml-string key path)))

(defun %write-key (key stream)
  (if (and (plusp (length key))
           (loop for character across key
                 always (toml-bare-key-character-p character)))
      (write-string key stream)
      (%write-string-value key stream nil)))

(defun %write-string-value (value stream path)
  (%validate-toml-string value path)
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
  (if (%toml-integer-in-range-p value)
      (princ value stream)
      (%signal-encoding-error "Integer is outside TOML's signed 64-bit range"
                              value path)))
(defun %write-fallback-value (value stream path)
  (cond ((hash-table-p value)
         (%validate-writer-table value path))
        ((integerp value)
         (%write-integer-value value stream path))
        (t
         (%signal-encoding-error "Unsupported TOML value" value path))))

(defun %write-float-value (value stream)
  (sb-int:with-float-traps-masked (:invalid)
    (cond ((sb-ext:float-nan-p value)
           (write-string (first +toml-nan-tokens+) stream))
          ((sb-ext:float-infinity-p value)
           (write-string (if (minusp value)
                             +toml-negative-infinity-token+
                             (first +toml-positive-infinity-tokens+))
                         stream))
          (t (let ((*read-default-float-format* 'double-float))
               (prin1 value stream))))))

(defun %write-inline-table (table stream path)
  (%with-writer-container table path t
    (if (zerop (hash-table-count table))
        (write-string "{}" stream)
        (progn
          (write-string "{ " stream)
          (let ((first t))
            (maphash (lambda (key value)
                       (%validate-writer-key key path)
                       (unless first (write-string ", " stream))
                       (setf first nil)
                       (%with-writer-path path key
                         (%write-key key stream)
                         (write-string " = " stream)
                         (%write-value value stream path)))
                     table))
          (write-string " }" stream)))))

(defun %array-of-tables-p (value)
  (and (plusp (length value))
       (loop for item across value always (hash-table-p item))))

(defun %write-array (value stream path)
  (%with-writer-container value path t
    (write-char #\[ stream)
    (loop for index from 0 below (length value)
          do (when (plusp index) (write-string ", " stream))
             (%with-writer-path path index
               (%write-value (aref value index) stream path)))
    (write-char #\] stream)))

(define-toml-emitter %write-value)

(defun %entry-kind (value)
  (cond ((hash-table-p value) :table)
        ((and (toml-array-p value) (%array-of-tables-p value)) :array-table)
        (t :value)))

(defun %write-key-path (path key stream)
  (loop for index below (length path)
        do (%write-key (aref path index) stream)
           (write-char #\. stream))
  (%write-key key stream))

(defun %write-table-header (key path stream opening closing)
  (write-string opening stream)
  (%write-key-path path key stream)
  (write-string closing stream)
  (write-char #\Newline stream))

(defun %write-array-table-sections (entries path stream)
  (dolist (entry entries)
    (let ((key (car entry))
          (value (cdr entry))
          (header-path (copy-seq path)))
      (%with-writer-path path key
        (%with-writer-container value path t
          (loop for item across value
                do (%write-table-header key header-path stream "[[" "]]")
                   (write-table item path stream)))))))

(defun write-table (table path stream &optional (nested-p t))
  (declare (type (and vector (not simple-array)) path))
  (%with-writer-container table path nested-p
    (%validate-writer-table table path)
    (let ((tables nil)
          (array-tables nil))
      (maphash (lambda (key value)
                 (%validate-writer-key key path)
                 (case (%entry-kind value)
                   (:value
                     (%write-key key stream)
                     (write-string " = " stream)
                     (%with-writer-path path key
                       (%write-value value stream path))
                     (write-char #\Newline stream))
                   (:table (push (cons key value) tables))
                   (:array-table (push (cons key value) array-tables))))
               table)
      (dolist (entry (nreverse tables))
        (let ((key (car entry))
              (value (cdr entry)))
          (%write-table-header key path stream "[" "]")
          (%with-writer-path path key
            (write-table value path stream))))
      (%write-array-table-sections (nreverse array-tables) path stream))))

(defun %write-root (value stream)
  (unless (hash-table-p value)
    (%signal-encoding-error "The top-level TOML value must be a hash-table"
                            value nil))
  ;; A root write must isolate its context, including during reentrant writes.
  (let ((*toml-writer-active-containers* nil))
    (%with-writer-context 0
      (write-table value (make-array 8 :adjustable t :fill-pointer 0)
                   stream nil))))

(defun write-toml (value stream)
  "Write VALUE as TOML to STREAM and return VALUE."
  (check-type stream stream)
  (%write-root value stream)
  value)

(defun encode (value)
  "Return VALUE encoded as TOML text."
  (with-output-to-string (stream)
    (write-toml value stream)))
