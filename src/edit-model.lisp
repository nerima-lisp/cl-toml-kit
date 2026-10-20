(in-package #:cl-toml-kit)

(defstruct (edit-assignment (:constructor %make-edit-assignment))
  path
  node
  line-start
  line-end)

(deftype edit-node-kind () '(member :value :array :inline))

(defstruct (edit-section (:constructor %make-edit-section))
  path start end)

(defstruct (edit-node (:constructor %make-edit-node))
  path-reversed
  start
  end
  (kind :value :type edit-node-kind)
  children
  assignment
  key-start)

(defun edit-node-path (node)
  (reverse (edit-node-path-reversed node)))

(defun %edit-fail (path format-control &rest arguments)
  (error (make-toml-format-preservation-error
          :path path :message (apply #'format nil format-control arguments))))

(defun %edit-byte-elements-p (value)
  (every (lambda (byte) (typep byte '(unsigned-byte 8))) value))

(defun %edit-byte-vector-p (value)
  (and (vectorp value)
       (not (stringp value))
       (%edit-byte-elements-p value)))

(defun %edit-normalize-path (path)
  (multiple-value-bind (component-limit limit-message)
      (%toml-limit :path-components)
    (let ((items (cond ((stringp path)
                        (when (zerop component-limit)
                          (%edit-fail nil "~A" limit-message))
                        (list path))
                       ((listp path)
                        (let ((cursor path)
                              (length 0))
                          (loop while (consp cursor)
                                do (incf length)
                                   (when (> length component-limit)
                                     (%edit-fail nil "~A" limit-message))
                                   (setf cursor (cdr cursor)))
                          (unless (null cursor)
                            (%edit-fail nil
                                        "Path must be a finite proper list")))
                        (copy-list path))
                       ((vectorp path)
                        (when (> (length path) component-limit)
                          (%edit-fail nil "~A" limit-message))
                        (coerce path 'list))
                       (t
                        (%edit-fail nil
                                    "Path must be a string, list, or vector")))))
      (unless items (%edit-fail path "Path must not be empty"))
      (dolist (item items)
        (unless (or (stringp item)
                    (and (integerp item) (not (minusp item))))
          (%edit-fail path
                      "Path components must be strings or non-negative integers")))
      items)))
