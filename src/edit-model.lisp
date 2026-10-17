(in-package #:cl-toml-kit)

(defstruct (edit-assignment (:constructor %make-edit-assignment))
  path node line-start line-end section)
(deftype edit-node-kind () '(member :value :array :inline))
(defstruct (edit-section (:constructor %make-edit-section))
  path start end)

(defstruct (edit-node (:constructor %make-edit-node)) path start end (kind :value :type edit-node-kind) children assignment key-start)

(defun %edit-fail (path format-control &rest arguments)
  (error (make-toml-format-preservation-error
          :path path :message (apply #'format nil format-control arguments))))

(defun %edit-byte-vector-p (value)
  (and (vectorp value)
       (not (stringp value))
       (every (lambda (byte) (typep byte '(unsigned-byte 8))) value)))

(defun %edit-normalize-path (path)
  (let ((items (cond ((stringp path) (list path))
                     ((listp path) (copy-list path))
                     ((vectorp path) (coerce path 'list))
                     (t (%edit-fail nil "Path must be a string, list, or vector")))))
    (unless items (%edit-fail path "Path must not be empty"))
    (dolist (item items)
      (unless (or (stringp item) (and (integerp item) (not (minusp item))))
        (%edit-fail path "Path components must be strings or non-negative integers")))
    items))

(defun %edit-make-node (path start end kind children assignment &optional key-start)
  (%make-edit-node :path path :start start :end end :kind kind
                   :children children :assignment assignment
                   :key-start key-start))
