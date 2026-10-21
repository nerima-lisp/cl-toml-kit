;;;; src/reader-path.lisp
(in-package #:cl-toml-kit)

(defun %path-length (path)
  (if (stringp path) 1 (length path)))

(defun %path-parent (path)
  (if (stringp path) nil (butlast path)))

(defun %path-last (path)
  (if (stringp path) path (car (last path))))

(defun %path-next (path)
  (values (car path) (cdr path)))
