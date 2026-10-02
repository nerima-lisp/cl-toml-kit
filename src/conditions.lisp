;;;; src/conditions.lisp
(in-package #:cl-toml-kit)

(defconstant +toml-diagnostic-limit+ 256)

(defun %diagnostic-string (value &optional (limit +toml-diagnostic-limit+))
  (let ((text (if (stringp value) value (princ-to-string value))))
    (with-output-to-string (out)
      (loop with n = 0
            for c across text
            for escaped = (case c
                            (#\Newline "\\n") (#\Return "\\r")
                            (#\Tab "\\t") (#\Backspace "\\b")
                            (otherwise (string c)))
            while (<= (+ n (length escaped)) limit)
            do (write-string escaped out)
               (incf n (length escaped))))))

(defun %diagnostic-path (path)
  (when path
    (loop for item in (if (listp path) path (list path))
          repeat 32
          collect (if (or (stringp item) (integerp item)) item
                      (%diagnostic-string item 64)))))

(define-condition toml-kit-error (error) ())

(define-condition toml-value-model-error (toml-kit-error)
  ((message :initarg :message :reader toml-value-model-error-message))
  (:report (lambda (condition stream)
             (write-string (toml-value-model-error-message condition) stream))))

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
             (format stream
                     "TOML parse error~@[ in ~A~] at line ~D, column ~D (position ~D)~@[ at ~S~]~@[; expected ~A~]"
                     (toml-parse-error-source-name condition)
                     (toml-parse-error-line condition)
                     (toml-parse-error-column condition)
                     (toml-parse-error-position condition)
                     (toml-parse-error-path condition)
                     (toml-parse-error-expected condition)))))

(defun make-toml-parse-error (&key source-name position line column path expected context text)
  (make-condition 'toml-parse-error
                  :source-name source-name :position position :line line :column column
                  :path (%diagnostic-path path)
                  :expected (and expected (%diagnostic-string expected 128))
                  :context (%diagnostic-string (or context "TOML"))
                  :text (%diagnostic-string (or text ""))))

(define-condition toml-encoding-error (toml-kit-error)
  ((message :initarg :message :initform "TOML encoding failed"
            :reader toml-encoding-error-message)
   (path :initarg :path :initform nil :reader toml-encoding-error-path))
  (:report (lambda (condition stream)
             (format stream "TOML encode error~@[ at ~S~]: ~A"
                     (toml-encoding-error-path condition)
                     (toml-encoding-error-message condition)))))

(defun make-toml-encoding-error (&key message path)
  (make-condition 'toml-encoding-error
                  :message (%diagnostic-string (or message "TOML encoding failed"))
                  :path (%diagnostic-path path)))
