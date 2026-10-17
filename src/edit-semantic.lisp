(in-package #:cl-toml-kit)

(declaim (ftype function %edit-semantic-change %edit-semantic-table-change %edit-semantic-array-change))

(defun %edit-copy-value (value)
  (cond
    ((hash-table-p value)
     (let ((copy (make-hash-table :test (hash-table-test value))))
       (maphash (lambda (key item)
                  (setf (gethash key copy) (%edit-copy-value item)))
                value)
       copy))
    ((vectorp value)
     (make-array (length value)
                 :initial-contents (loop for item across value
                                         collect (%edit-copy-value item))))
    (t value)))

(defun %edit-value-equal-p (left right)
  (cond
    ((and (hash-table-p left) (hash-table-p right))
     (and (= (hash-table-count left) (hash-table-count right))
          (block equal-table
            (maphash
             (lambda (key value)
               (multiple-value-bind (other present) (gethash key right)
                 (unless (and present (%edit-value-equal-p value other))
                   (return-from equal-table nil))))
             left)
            t)))
    ((and (vectorp left) (vectorp right))
     (and (= (length left) (length right))
          (loop for index below (length left)
                always (%edit-value-equal-p (aref left index)
                                             (aref right index)))))
    ((or (hash-table-p left) (hash-table-p right)
         (vectorp left) (vectorp right))
     nil)
    (t (equalp left right))))

(defun %edit-semantic-change (container path new-value delete-p)
  (let ((component (car path))
        (rest (cdr path)))
    (cond
      ((hash-table-p container)
       (%edit-semantic-table-change container component rest path new-value delete-p))
      ((vectorp container)
       (%edit-semantic-array-change container component rest path new-value delete-p))
      (t
       (%edit-fail path "Edited path does not traverse a TOML table or array")))))

(defun %edit-semantic-array-change (container component rest path new-value delete-p)
  (unless (and (integerp component)
               (<= 0 component)
               (if (or delete-p rest)
                   (< component (length container))
                   (<= component (length container))))
    (%edit-fail path "An array index is outside the parsed TOML value"))
  (if rest
      (progn
        (setf (aref container component)
              (%edit-semantic-change (aref container component)
                                     rest new-value delete-p))
        container)
      (if delete-p
          (make-array (1- (length container))
                      :initial-contents
                      (loop for index below (length container)
                            unless (= index component)
                              collect (aref container index)))
          (if (= component (length container))
              (make-array (1+ (length container))
                          :initial-contents
                          (append (loop for item across container collect item)
                                  (list new-value)))
              (progn
                (setf (aref container component) new-value)
                container)))))

(defun %edit-semantic-table-change (container component rest path new-value delete-p)
  (if rest
      (multiple-value-bind (child present) (gethash component container)
        (unless present
          (%edit-fail path "Edited path is absent from parsed TOML"))
        (setf (gethash component container)
              (%edit-semantic-change child rest new-value delete-p))
        container)
      (progn
        (unless (stringp component)
          (%edit-fail path "A TOML table requires a string key"))
        (if delete-p
            (multiple-value-bind (value present) (gethash component container)
              (declare (ignore value))
              (unless present
                (%edit-fail path "Deleted path is absent from parsed TOML"))
              (remhash component container))
            (setf (gethash component container) new-value))
        container)))
