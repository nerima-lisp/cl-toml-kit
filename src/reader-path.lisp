(in-package #:cl-toml-kit)

(defun %path-length (path)
  (if (stringp path) 1 (length path)))

(defun %path-parent (path)
  (if (stringp path) nil (butlast path)))

(defun %path-last (path)
  (if (stringp path) path (car (last path))))

(defun %path-next (path)
  (if (stringp path)
      (values path nil)
      (values (car path) (cdr path))))
