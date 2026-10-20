(in-package #:cl-toml-kit)

(defun %edit-key-text (key)
  (with-output-to-string (stream) (%write-key key stream)))

(defun %edit-key-path-text (path)
  (with-output-to-string (stream)
    (loop for item in path
          for first = t then nil
          do (unless first (write-char #\. stream))
             (write-string (%edit-key-text item) stream))))

(defun %edit-replacement (positions start end replacement)
  (list (aref positions start) (aref positions end)
        (if (%edit-byte-vector-p replacement)
            replacement
            (%edit-string-to-bytes replacement))))

(defun %edit-delete-range (text node parent)
  (if (null parent)
      (let ((assignment (edit-node-assignment node)))
        (list (edit-assignment-line-start assignment)
              (edit-assignment-line-end assignment)
              (make-array 0 :element-type '(unsigned-byte 8))))
      (let* ((children (edit-node-children parent))
             (position (position node children :test #'eq))
             (previous (and (plusp position) (nth (1- position) children)))
             (next (and (< (1+ position) (length children))
                        (nth (1+ position) children))))
        (if (eq (edit-node-kind parent) :inline)
            (%edit-inline-delete-range node previous next)
            (%edit-sequence-delete-range text node parent previous next)))))

(defun %edit-trivia-line-p (text start end)
  (let ((first (%edit-horizontal-space text start end)))
    (or (= first end)
        (char= (char text first) #\#))))

(defun %edit-section-insert-position (text section)
  (let ((position (edit-section-end section))
        (section-start (edit-section-start section)))
    (loop
      (when (<= position section-start)
        (return position))
      (let* ((newline (position #\Newline text :end position :from-end t))
             (line-start (if newline (1+ newline) 0)))
        (cond
          ((= line-start position)
           (if (and newline
                    (%edit-trivia-line-p
                     text
                     (1+ (or (position #\Newline text :end newline :from-end t)
                             (1- section-start)))
                     newline))
               (setf position newline)
               (return position)))
          ((and (>= line-start section-start)
                (%edit-trivia-line-p text line-start position))
           (setf position line-start))
          (t (return position)))))))

(defun %edit-deletion-has-comment-p (text start end)
  (or (position #\# text :start start :end end)
      (let* ((current-newline (position #\Newline text :end start :from-end t))
             (previous-newline (and current-newline
                                    (position #\Newline text :end current-newline
                                              :from-end t)))
             (previous-start (if previous-newline (1+ previous-newline) 0))
             (previous-end current-newline))
        (and previous-end
             (< previous-start previous-end)
             (char= (char text (%edit-horizontal-space text previous-start
                                                        previous-end)) #\#)))))

(defun %edit-section-for-path (sections path)
  (find path sections :key #'edit-section-path :test #'equal))

(defun %edit-path-prefix-p (prefix path)
  (and (<= (length prefix) (length path))
       (loop for left in prefix
             for right in path
             always (equal left right))))

(defun %edit-insert-line (text section key-path value)
  (let* ((position (%edit-section-insert-position text section))
         (line-ending (%edit-line-ending text position))
         (prefix (if (and (plusp position)
                          (not (member (char text (1- position))
                                       '(#\Newline #\Return))))
                     line-ending ""))
         (line (format nil "~A = ~A~A" (%edit-key-path-text key-path)
                       value line-ending)))
    (list position position (concatenate 'string prefix line))))

(defun %edit-insert-inline (text node key value)
  (let ((separator (if (edit-node-children node) ", " ""))
        (position (- (edit-node-end node) 2)))
    (loop while (and (> position (edit-node-start node))
                     (toml-space-character-p (char text position)))
          do (decf position))
    (incf position)
    (list position position
          (format nil "~A~A = ~A" separator (%edit-key-text key) value))))

(defun %edit-array-insertion-position (text node children)
  (let ((position (1- (edit-node-end node))))
    (when (position #\# text
                    :start (if children
                               (edit-node-end (car (last children)))
                               (1+ (edit-node-start node)))
                    :end (edit-node-end node))
      (%edit-fail (edit-node-path node)
                  "Array insertion cannot preserve a trailing comment"))
    (loop while (and (> position (edit-node-start node))
                     (or (toml-space-character-p (char text (1- position)))
                         (member (char text (1- position))
                                 '(#\Newline #\Return))))
          do (decf position))
    (if (and children
             (> position (edit-node-start node))
             (char= (char text (1- position)) #\,))
        (1- position)
        position)))

(defun %edit-array-insertion-separator
    (text node insertion-position)
  (let* ((multiline (find #\Newline text
                          :start (edit-node-start node)
                          :end (edit-node-end node)))
         (line-ending (%edit-line-ending text insertion-position))
         (line-start (or (position #\Newline text
                                   :end insertion-position
                                   :from-end t)
                         -1))
         (indent-start (1+ line-start))
         (indent-end indent-start))
    (loop while (and (< indent-end insertion-position)
                     (toml-space-character-p (char text indent-end)))
          do (incf indent-end))
    (if multiline
        (format nil ",~A~A" line-ending
                (subseq text indent-start indent-end))
        ", ")))

(defun %edit-insert-array (text node value)
  (let* ((children (edit-node-children node))
         (position (%edit-array-insertion-position text node children))
         (separator (%edit-array-insertion-separator text node position)))
    (list position position
          (if children
              (format nil "~A~A" separator value)
              value))))

(defun %edit-apply-bytes (source replacements)
  (let* ((ordered (sort (copy-list replacements) #'< :key #'first))
         (size (length source))
         (delta 0))
    (dolist (replacement ordered)
      (incf delta (- (length (third replacement))
                     (- (second replacement) (first replacement)))))
    (let ((result (make-array (+ size delta) :element-type '(unsigned-byte 8)))
          (cursor 0) (output 0))
      (dolist (replacement ordered)
        (destructuring-bind (start end bytes) replacement
          (when (< start cursor) (%edit-fail nil "Overlapping edit ranges"))
          (replace result source :start1 output :start2 cursor :end2 start)
          (incf output (- start cursor))
          (replace result bytes :start1 output)
          (incf output (length bytes))
          (setf cursor end)))
      (replace result source :start1 output :start2 cursor :end2 size)
      result)))

(defun %edit-inline-delete-range (node previous next)
  (cond
    (next
     (list (edit-node-key-start node) (edit-node-key-start next)
           (make-array 0 :element-type '(unsigned-byte 8))))
    (previous
     (list (edit-node-end previous) (edit-node-end node)
           (make-array 0 :element-type '(unsigned-byte 8))))
    (t
     (list (edit-node-key-start node) (edit-node-end node)
           (make-array 0 :element-type '(unsigned-byte 8))))))

(defun %edit-sequence-delete-range (text node parent previous next)
  (cond
    (next
     (list (edit-node-start node) (edit-node-start next)
           (make-array 0 :element-type '(unsigned-byte 8))))
    (previous
     (list (edit-node-end previous) (edit-node-end node)
           (make-array 0 :element-type '(unsigned-byte 8))))
    (t
     (let ((end (edit-node-end node)))
       (when (and (eq (edit-node-kind parent) :array)
                  (< end (edit-node-end parent))
                  (char= (char text end) #\,))
         (incf end))
       (list (edit-node-start node) end
             (make-array 0 :element-type '(unsigned-byte 8)))))))
