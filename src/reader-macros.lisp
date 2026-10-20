;;;; src/reader-macros.lisp
(in-package #:cl-toml-kit)

(defmacro define-char-class (name table)
  (let ((character (gensym "CHARACTER")))
    `(progn
       (declaim (inline ,name))
       (defun ,name (,character)
         (declare (type (or null character) ,character))
         (and ,character (< (char-code ,character) 128)
              (= 1 (sbit ,table (char-code ,character))))))))

;; A failure continuation must not return.
(defmacro define-toml-rule (name (state position success failure) &body body)
  `(defun ,name (,state ,position ,success ,failure)
     (declare (type toml-reader-state ,state)
              (type fixnum ,position)
              (type function ,success ,failure)
              (optimize (speed 3) (safety 1)))
     (setf (toml-reader-state-position ,state) ,position)
     ,@body))

(define-char-class toml-bare-key-character-p +toml-bare-key-table+)
(define-char-class toml-decimal-character-p +toml-decimal-table+)
(define-char-class toml-space-character-p +toml-space-table+)
(define-char-class toml-control-character-p +toml-control-table+)
(define-char-class %toml-value-terminator-p +toml-value-terminator-table+)
