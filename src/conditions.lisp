;;;; src/conditions.lisp
(in-package #:cl-toml-kit)

(defconstant +toml-diagnostic-limit+ 256)

(defun %diagnostic-string (value &optional (limit +toml-diagnostic-limit+))
  (let ((text (cond ((stringp value) value)
                    ((pathnamep value) (namestring value))
                    ((null value) "null")
                    ((integerp value) "integer")
                    ((characterp value) (string value))
                    ((symbolp value) (symbol-name value))
                    ((floatp value) "float")
                    ((hash-table-p value) "table")
                    ((vectorp value) "array")
                    ((consp value) "list")
                    (t "value"))))
    (with-output-to-string (out)
      (loop with n = 0
            for c across text
            for code = (char-code c)
            for escaped = (cond ((member c (list #\Newline #\Return #\Tab #\Backspace))
                                 (aref *toml-basic-string-escape* code))
                                ((or (< code 32)
                                     (<= #x7f code #x9f)
                                     (<= #xd800 code #xdfff))
                                 (format nil "\\u~4,'0X" code))
                                (t (string c)))
            while (<= (+ n (length escaped)) limit)
            do (write-string escaped out)
               (incf n (length escaped))))))

(defconstant +toml-diagnostic-path-component-limit+ 64)
(defconstant +toml-diagnostic-path-limit+ 256)
(defconstant +toml-diagnostic-path-item-limit+ 32)
(defconstant +toml-diagnostic-path-ellipsis+ :...)

(defun %diagnostic-path-rendered-size (value)
  (let ((*print-base* 10)
        (*print-radix* nil)
        (*print-case* :upcase)
        (*print-pretty* nil)
        (*print-escape* t)
        (*print-readably* t)
        (*print-length* nil)
        (*print-level* nil))
    (length (write-to-string value))))

(defun %diagnostic-path-string (value rendered-limit)
  (or (loop for prefix-length downfrom (min (length value) rendered-limit) to 0
            for truncated-p = (< prefix-length (length value))
            for prefix-end = (if truncated-p
                                 (max 0 (- prefix-length 3))
                               prefix-length)
            for candidate = (if truncated-p
                                (concatenate 'string
                                             (subseq value 0 prefix-end)
                                             "...")
                              (subseq value 0 prefix-end))
            when (<= (%diagnostic-path-rendered-size candidate) rendered-limit)
            return candidate)
      ""))

(defun %diagnostic-path-component (item rendered-limit)
  (labels ((safe-string (value)
                        (let ((scan-limit (min (length value)
                                               +toml-diagnostic-path-component-limit+
                                               (max 0 rendered-limit))))
                          (with-output-to-string (out)
                            (loop for index from 0 below scan-limit
                                  for character = (char value index)
                                  for code = (char-code character)
                                  do (if (or (< code 32)
                                             (<= #x7f code #x9f)
                                             (<= #xd800 code #xdfff))
                                         (format out "\\u~4,'0X" code)
                                       (write-char character out)))
                            (when (< scan-limit (length value))
                              (write-string "..." out))))))
    (cond ((eq item +toml-diagnostic-path-ellipsis+) item)
          ((stringp item)
           (%diagnostic-path-string (safe-string item) rendered-limit))
          ((and (integerp item) (typep item 'fixnum))
           (if (<= (%diagnostic-path-rendered-size item) rendered-limit)
               item
             (%diagnostic-path-string "integer" rendered-limit)))
          ((integerp item)
           (%diagnostic-path-string "integer" rendered-limit))
          ((null item)
           (%diagnostic-path-string "null" rendered-limit))
          ((symbolp item)
           (%diagnostic-path-string (safe-string (symbol-name item)) rendered-limit))
          ((characterp item)
           (%diagnostic-path-string (safe-string (string item)) rendered-limit))
          ((floatp item)
           (%diagnostic-path-string "float" rendered-limit))
          ((hash-table-p item)
           (%diagnostic-path-string "table" rendered-limit))
          ((vectorp item)
           (%diagnostic-path-string "array" rendered-limit))
          ((consp item)
           (%diagnostic-path-string "list" rendered-limit))
          (t
           (%diagnostic-path-string "value" rendered-limit)))))

(defun %diagnostic-path (path)
  (when path
    (let ((remaining (if (consp path) path (list path)))
          (items '())
          (rendered-length 2)
          (item-count 0)
          (truncated nil)
          (ellipsis-size
           (%diagnostic-path-rendered-size +toml-diagnostic-path-ellipsis+)))
      (loop while (consp remaining)
            do (when (>= item-count +toml-diagnostic-path-item-limit+)
                 (setf truncated t)
                 (return))
            (let* ((tail (cdr remaining))
                   (more-p (not (null tail)))
                   (separator-size (if items 1 0))
                   (reserved-size (if more-p (1+ ellipsis-size) 0))
                   (available (- +toml-diagnostic-path-limit+
                                 rendered-length
                                 separator-size
                                 reserved-size))
                   (component (and (not (minusp available))
                                   (%diagnostic-path-component
                                    (car remaining)
                                    (min +toml-diagnostic-path-component-limit+
                                         available))))
                   (component-size (and component
                                        (%diagnostic-path-rendered-size
                                         component))))
              (if (and component-size (<= component-size available))
                  (progn
                    (push component items)
                    (incf rendered-length
                          (+ separator-size component-size))
                    (incf item-count)
                    (setf remaining tail))
                (progn
                  (setf truncated t)
                  (return)))))
      (when (and (not truncated) remaining)
        (setf truncated t))
      (when truncated
        (push +toml-diagnostic-path-ellipsis+ items))
      (nreverse items))))

(defun %diagnostic-path-report-string (path)
  (when path
    (let ((*print-base* 10)
          (*print-radix* nil)
          (*print-case* :upcase)
          (*print-pretty* nil)
          (*print-escape* t)
          (*print-readably* t)
          (*print-length* nil)
          (*print-level* nil))
      (write-to-string (%diagnostic-path path)))))

(define-condition toml-kit-error (error) ())

(define-condition toml-value-model-error (toml-kit-error)
  ((message :initarg :message :initform "Invalid TOML value model"
            :reader toml-value-model-error-message))
  (:report (lambda (condition stream)
             (let ((message (toml-value-model-error-message condition)))
               (write-string (%diagnostic-string message) stream)))))

(define-condition toml-parse-error (toml-kit-error)
  ((source-name :initarg :source-name :initform nil
                :reader toml-parse-error-source-name)
   (position :initarg :position :initform 0 :reader toml-parse-error-position)
   (line :initarg :line :initform 1 :reader toml-parse-error-line)
   (column :initarg :column :initform 1 :reader toml-parse-error-column)
   (path :initarg :path :initform nil :reader toml-parse-error-path)
   (expected :initarg :expected :initform nil :reader toml-parse-error-expected)
   (context :initarg :context :initform "TOML" :reader toml-parse-error-context)
   (text :initarg :text :initform "" :reader toml-parse-error-text))
  (:report (lambda (condition stream)
             (let* ((source-name (toml-parse-error-source-name condition))
                    (expected (toml-parse-error-expected condition))
                    (line (toml-parse-error-line condition))
                    (column (toml-parse-error-column condition))
                    (position (toml-parse-error-position condition))
                    (line-text (if (integerp line) (format nil "~D" line)
                                   (%diagnostic-string line)))
                    (column-text (if (integerp column) (format nil "~D" column)
                                     (%diagnostic-string column)))
                    (position-text (if (integerp position) (format nil "~D" position)
                                       (%diagnostic-string position)))
                    (location-text
                     (cond
                       ((and (integerp line) (integerp column))
                        (format nil "at line ~D, column ~D (position ~A)"
                                line column position-text))
                       ((and line column)
                        (format nil "at line ~A, column ~A (position ~A)"
                                line-text column-text position-text))
                       (t (format nil "at position ~A" position-text)))))
               (format stream
                       "TOML parse error~@[ in ~A~] ~A~@[ at ~A~]~@[; expected ~A~]"
                       (and source-name (%diagnostic-string source-name))
                       location-text
                       (%diagnostic-path-report-string
                        (toml-parse-error-path condition))
                       (and expected (%diagnostic-string expected 128)))))))

(defun make-toml-parse-error (&key source-name position line column path expected context text)
  (make-condition 'toml-parse-error
                  :source-name (and source-name (%diagnostic-string source-name))
                  :position position :line line :column column
                  :path (%diagnostic-path path)
                  :expected (and expected (%diagnostic-string expected 128))
                  :context (%diagnostic-string (or context "TOML"))
                  :text (%diagnostic-string (or text ""))))

(define-condition toml-encoding-error (toml-kit-error)
  ((message :initarg :message :initform "TOML encoding failed"
            :reader toml-encoding-error-message)
   (path :initarg :path :initform nil :reader toml-encoding-error-path))
  (:report (lambda (condition stream)
             (let ((message (toml-encoding-error-message condition)))
               (format stream "TOML encode error~@[ at ~A~]: ~A"
                       (%diagnostic-path-report-string (toml-encoding-error-path condition))
                       (if (null message) "NIL" (%diagnostic-string message)))))))

(defun make-toml-encoding-error (&key message path)
  (make-condition 'toml-encoding-error
                  :message (%diagnostic-string (or message "TOML encoding failed"))
                  :path (%diagnostic-path path)))

(define-condition toml-format-preservation-error (toml-kit-error)
  ((message :initarg :message :initform "TOML format-preserving edit was rejected"
            :reader toml-format-preservation-error-message)
   (path :initarg :path :initform nil :reader toml-format-preservation-error-path))
  (:report (lambda (condition stream)
             (let ((message (toml-format-preservation-error-message condition)))
               (format stream "TOML format-preserving edit error~@[ at ~A~]: ~A"
                       (%diagnostic-path-report-string (toml-format-preservation-error-path condition))
                       (if (null message) "NIL" (%diagnostic-string message)))))))

(defun make-toml-format-preservation-error (&key message path)
  (make-condition 'toml-format-preservation-error
                  :message (%diagnostic-string
                            (or message "TOML format-preserving edit was rejected"))
                  :path (%diagnostic-path path)))
