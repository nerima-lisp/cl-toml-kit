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
  `(defun ,name (,state ,position continuation)
     (declare (type toml-reader-state ,state)
              (type fixnum ,position)
              (type function continuation)
              (optimize (speed 3) (safety 1)))
     (setf (toml-reader-state-position ,state) ,position)
     ,@body))

(define-char-class toml-bare-key-character-p +toml-bare-key-table+)
(define-char-class toml-decimal-character-p +toml-decimal-table+)
(define-char-class toml-space-character-p +toml-space-table+)
(define-char-class toml-control-character-p +toml-control-table+)
