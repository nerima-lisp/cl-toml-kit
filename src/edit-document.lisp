(in-package #:cl-toml-kit)

(defun %edit-header-context (path latest)
  (let ((result nil) (prefix nil))
    (dolist (component path result)
      (push component prefix)
      (setf prefix (nreverse prefix))
      (let ((index (gethash prefix latest)))
        (setf result (append result (list component)))
        (when index (setf result (append result (list index)))))
      (setf prefix (reverse prefix)))))

(defun %edit-array-table-counter-path (header latest)
  (append (%edit-header-context (butlast header) latest)
          (last header)))

(defun %edit-array-table-context
    (header latest counts
     &key (array-table-counter-path #'%edit-array-table-counter-path))
  (let* ((counter-path
           (funcall array-table-counter-path header latest))
         (index (gethash counter-path counts 0)))
    (setf (gethash counter-path counts) (1+ index)
          (gethash header latest) index)
    (%edit-header-context header latest)))

(defun %edit-scan-header-line
    (text line-start first length latest counts
     &key (array-table-counter-path #'%edit-array-table-counter-path))
  (let* ((array-p (and (< (1+ first) length)
                       (char= (char text (1+ first)) #\[)))
         (key-start (+ first (if array-p 2 1))))
    (multiple-value-bind (header next)
        (%edit-scan-key-path text key-start length)
      (setf next (%edit-horizontal-space text next length))
      (when (and (< next length)
                 (char= (char text next) #\])
                 array-p)
        (incf next))
      (unless (and (< next length) (char= (char text next) #\]))
        (%edit-fail header "Invalid table header"))
      (values (if array-p
                  (%edit-array-table-context
                   header latest counts
                   :array-table-counter-path array-table-counter-path)
                  (%edit-header-context header latest))
              (%edit-line-end text line-start)))))

(defun %edit-scan-assignment-line (text line-start first length current-section)
  (multiple-value-bind (keys next) (%edit-scan-key-path text first length)
    (setf next (%edit-horizontal-space text next length))
    (unless (and (< next length) (char= (char text next) #\=))
      (%edit-fail keys "Assignment has no equals sign"))
    (incf next)
    (setf next (%edit-horizontal-space text next length))
    (multiple-value-bind (nesting-limit nesting-message)
        (%toml-limit :nesting-depth)
      (let* ((path (append (edit-section-path current-section) keys))
             (path-reversed (reverse path))
             (assignment
               (%make-edit-assignment :path path :line-start line-start :line-end nil))
             (node (%edit-scan-value-node text next length path-reversed assignment
                                          0 nesting-limit nesting-message)))
        (setf (edit-assignment-node assignment) node
              (edit-assignment-line-end assignment)
              (%edit-line-end text (edit-node-end node)))
        (values assignment (edit-assignment-line-end assignment))))))

(defun %edit-trivia-or-comment-line-p (text first length)
  (or (= first length)
      (member (char text first) +toml-newline-characters+)
      (char= (char text first) #\#)))

(defun %edit-line-ending (text &optional position)
  (let* ((limit (or position (length text)))
         (previous (position +toml-line-feed+ text :end limit :from-end t))
         (next (position +toml-line-feed+ text :start limit)))
    (cond
      ((and previous (> previous 0)
            (char= (char text (1- previous)) +toml-carriage-return+))
       (coerce (list +toml-carriage-return+ +toml-line-feed+) 'string))
      (previous (string +toml-line-feed+))
      ((and next (> next 0)
            (char= (char text (1- next)) +toml-carriage-return+))
       (coerce (list +toml-carriage-return+ +toml-line-feed+) 'string))
      (t (string +toml-line-feed+)))))

(defun %edit-scan-document
    (text &key (array-table-counter-path #'%edit-array-table-counter-path))
  (let* ((length (length text))
         (index 0)
         (assignments nil)
         (sections nil)
         (latest (make-hash-table :test #'equal))
         (counts (make-hash-table :test #'equal))
         (current-section (%make-edit-section :path nil :start 0 :end length)))
    (labels ((close-section (end)
               (setf (edit-section-end current-section) end)
               (push current-section sections)))
      (loop while (< index length)
            do (let* ((line-start index)
                      (first (%edit-horizontal-space text index length)))
                 (cond
                   ((%edit-trivia-or-comment-line-p text first length)
                    (setf index (%edit-line-end text line-start)))
                   ((char= (char text first) #\[)
                    (multiple-value-bind (path next)
                        (%edit-scan-header-line
                         text line-start first length latest counts
                         :array-table-counter-path array-table-counter-path)
                      (close-section line-start)
                      (setf current-section
                            (%make-edit-section :path path :start next :end length)
                            index next)))
                   (t
                    (multiple-value-bind (assignment next)
                        (%edit-scan-assignment-line
                         text line-start first length current-section)
                      (push assignment assignments)
                      (setf index next))))))
      (close-section length)
      (values (nreverse assignments) (nreverse sections)))))

(defun %edit-collect-nodes (assignments path)
  (let ((matches nil)
        (path-reversed (reverse path)))
    (labels ((visit (node parent)
               (when (equal path-reversed (edit-node-path-reversed node))
                 (push (cons node parent) matches))
               (dolist (child (edit-node-children node)) (visit child node))))
      (dolist (assignment assignments)
        (visit (edit-assignment-node assignment) nil)))
    (nreverse matches)))
