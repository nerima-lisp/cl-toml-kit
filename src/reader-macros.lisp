;;;; src/reader-macros.lisp
(in-package #:cl-toml-kit)

(defmacro define-char-class (name table)
  `(progn
     (declaim (inline ,name))
     (defun ,name (char)
       (declare (type (or null character) char))
       (and char (< (char-code char) 128)
            (= 1 (sbit ,table (char-code char)))))))

(defmacro define-toml-rule (name (state position) &body body)
  (let ((original-continuation (gensym "CONTINUATION"))
        (next-position (gensym "NEXT-POSITION"))
        (continue-function (gensym "CONTINUE")))
    `(defun ,name (,state ,position continuation)
       (declare (type toml-reader-state ,state)
                (type fixnum ,position)
                (type function continuation)
                (optimize (speed 3) (safety 1)))
       (setf (toml-reader-state-position ,state) ,position)
       (let ((,original-continuation continuation))
         (labels ((,continue-function (value ,next-position)
                    (declare (type fixnum ,next-position))
                    (setf (toml-reader-state-position ,state) ,next-position)
                    (funcall ,original-continuation value ,next-position)))
           (declare (inline ,continue-function))
           (let ((continuation #',continue-function))
             ,@body))))))

(defmacro with-toml-reader-depth ((state position) &body body)
  "Run BODY one aggregate level deeper, signaling a located parse error first."
  (let ((state-var (gensym "STATE")))
    `(let ((,state-var ,state))
       (when (and (toml-reader-state-max-depth ,state-var)
                  (>= (toml-reader-state-depth ,state-var)
                      (toml-reader-state-max-depth ,state-var)))
         (error (make-toml-parse-error
                 :source-name (toml-reader-state-source-name ,state-var)
                 :position ,position
                 :line (toml-reader-state-line ,state-var)
                 :column (toml-reader-state-column ,state-var)
                 :path (toml-reader-state-path ,state-var)
                 :expected "shallower nesting"
                 :text (toml-reader-state-source ,state-var))))
       (incf (toml-reader-state-depth ,state-var))
       (unwind-protect (progn ,@body)
         (decf (toml-reader-state-depth ,state-var))))))

(define-char-class toml-bare-key-character-p +toml-bare-key-table+)
(define-char-class toml-decimal-character-p +toml-decimal-table+)
(define-char-class toml-space-character-p +toml-space-table+)
(define-char-class toml-control-character-p +toml-control-table+)
