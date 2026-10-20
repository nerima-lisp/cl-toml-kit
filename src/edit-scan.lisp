(in-package #:cl-toml-kit)

(defun %edit-char (text position limit)
  (when (< position limit) (char text position)))

(defun %edit-horizontal-space (text position limit)
  (loop while (and (< position limit)
                   (toml-space-character-p (char text position)))
        do (incf position)
        finally (return position)))

(defun %edit-line-end (text position)
  (let ((length (length text)))
    (loop while (and (< position length)
                     (not (member (char text position)
                                  +toml-newline-characters+)))
          do (incf position))
    (cond ((and (< position length)
                (char= (char text position) +toml-carriage-return+)
                (< (1+ position) length)
                (char= (char text (1+ position)) +toml-line-feed+))
           (+ position 2))
          ((< position length) (1+ position))
          (t position))))

(defun %edit-skip-comment-and-trivia (text position limit)
  (loop
    (setf position (%edit-horizontal-space text position limit))
    (cond
      ((and (< position limit) (char= (char text position) #\#))
       (setf position (%edit-line-end text position)))
      ((and (< position limit)
            (member (char text position) +toml-newline-characters+))
       (setf position (%edit-line-end text position)))
      (t (return position)))))

(defun %edit-decode-basic-string (text start end)
  (with-output-to-string (out)
    (loop with index = (1+ start)
          while (< index (1- end))
          do (let ((character (char text index)))
               (if (char/= character #\\)
                   (write-char character out)
                   (progn
                     (incf index)
                     (let* ((escape (char text index))
                            (escape-position
                              (position escape +toml-escape-letters+ :test #'char=)))
                       (cond
                         ((and escape-position
                               (not (%toml-hex-escape-width escape)))
                          (write-char (aref +toml-escape-table+ escape-position) out))
                         ((%toml-hex-escape-width escape)
                          (let ((digits (%toml-hex-escape-width escape))
                                (value 0))
                            (dotimes (ignore digits)
                              (incf index)
                              (setf value (+ (* value 16)
                                             (%toml-hex-digit-value (char text index)))))
                            (write-char (code-char value) out)))
                         (t (write-char escape out))))))
               (incf index)))))

(defun %edit-scan-string-triple-end (text delimiter index limit)
  (let ((end index))
    (loop while (and (< end limit)
                     (char= (char text end) delimiter))
          do (incf end))
    (values end (>= (- end index) 3))))

(defun %edit-scan-string-step (text delimiter triple index limit)
  (cond
    ((and (char= delimiter #\")
          (char= (char text index) #\\))
     (values (+ index 2) nil))
    ((and triple (char= (char text index) delimiter))
     (%edit-scan-string-triple-end text delimiter index limit))
    ((and (not triple) (char= (char text index) delimiter))
     (values (1+ index) t))
    (t
     (values (1+ index) nil))))

(defun %edit-scan-string (text position limit)
  (let* ((delimiter (char text position))
         (triple (and (<= (+ position 2) (1- limit))
                      (char= delimiter (char text (1+ position)))
                      (char= delimiter (char text (+ position 2)))))
         (index (+ position (if triple 3 1))))
    (loop while (< index limit)
          do (multiple-value-bind (next done-p)
                 (%edit-scan-string-step
                  text delimiter triple index limit)
               (setf index next)
               (when done-p
                 (return-from %edit-scan-string index))))
    (%edit-fail nil "Unterminated string while editing TOML")))

(defun %edit-scan-key-component (text position limit)
  (let ((character (%edit-char text position limit)))
    (cond
      ((member character '(#\" #\'))
       (let ((end (%edit-scan-string text position limit)))
         (values (if (char= character #\")
                     (%edit-decode-basic-string text position end)
                     (subseq text (1+ position) (1- end)))
                 end)))
      ((and character (toml-bare-key-character-p character))
       (let ((end position))
         (loop while (and (< end limit)
                          (toml-bare-key-character-p (char text end)))
               do (incf end))
         (values (subseq text position end) end)))
      (t (%edit-fail nil "Invalid key while editing TOML")))))

(defun %edit-scan-key-path (text position limit)
  (let ((keys nil)
        (index position))
    (loop
      (setf index (%edit-horizontal-space text index limit))
      (multiple-value-bind (key next) (%edit-scan-key-component text index limit)
        (push key keys)
        (setf index (%edit-horizontal-space text next limit)))
      (if (and (< index limit) (char= (char text index) #\.))
          (incf index)
          (return (values (nreverse keys) index))))))

(declaim (ftype function %edit-scan-value-node))

(defun %edit-scan-array-node (text position limit path-reversed assignment
                              depth nesting-limit nesting-message)
  (let ((index (1+ position)) (children nil) (element-index 0))
    (loop
      (setf index (%edit-skip-comment-and-trivia text index limit))
      (when (and (< index limit) (char= (char text index) #\]))
        (return (%make-edit-node :path-reversed path-reversed
                                 :start position
                                 :end (1+ index)
                                 :kind :array
                                 :children (nreverse children)
                                 :assignment assignment)))
      (let ((child (%edit-scan-value-node
                    text index limit (cons element-index path-reversed)
                    assignment depth nesting-limit nesting-message)))
        (push child children)
        (incf element-index)
        (setf index (edit-node-end child))
        (setf index (%edit-skip-comment-and-trivia text index limit))
        (cond
          ((and (< index limit) (char= (char text index) #\,))
           (incf index))
          ((and (< index limit) (char= (char text index) #\])))
          (t (%edit-fail (reverse path-reversed)
                         "Array value has no closing bracket")))))))

(defun %edit-scan-inline-node (text position limit path-reversed assignment
                               depth nesting-limit nesting-message)
  (let ((index (1+ position)) (children nil))
    (loop
      (setf index (%edit-skip-comment-and-trivia text index limit))
      (when (and (< index limit) (char= (char text index) #\}))
        (return (%make-edit-node :path-reversed path-reversed
                                 :start position
                                 :end (1+ index)
                                 :kind :inline
                                 :children (nreverse children)
                                 :assignment assignment)))
      (let ((key-start index))
        (multiple-value-bind (keys next) (%edit-scan-key-path text index limit)
          (setf index (%edit-horizontal-space text next limit))
          (unless (and (< index limit) (char= (char text index) #\=))
            (%edit-fail (reverse path-reversed)
                        "Inline table entry has no equals sign"))
          (incf index)
          (setf index (%edit-horizontal-space text index limit))
          (let ((child-path path-reversed))
            (dolist (key keys)
              (push key child-path))
            (let ((child (%edit-scan-value-node
                          text index limit child-path assignment depth
                          nesting-limit nesting-message)))
              (setf (edit-node-key-start child) key-start)
              (push child children)
              (setf index (edit-node-end child))))
          (setf index (%edit-horizontal-space text index limit))
          (cond
            ((and (< index limit) (char= (char text index) #\,))
             (incf index))
            ((and (< index limit) (char= (char text index) #\})))
            (t (%edit-fail (reverse path-reversed)
                           "Inline table has no closing brace"))))))))

(defun %edit-scan-scalar-node (text position limit path-reversed assignment)
  (let ((end position))
    (loop while (and (< end limit)
                     (not (%toml-value-terminator-p (char text end))))
          do (incf end))
    (loop while (and (> end position)
                     (toml-space-character-p (char text (1- end))))
          do (decf end))
    (%make-edit-node :path-reversed path-reversed
                     :start position
                     :end end
                     :kind :value
                     :children nil
                     :assignment assignment)))

(defun %edit-scan-value-node
    (text position limit path-reversed assignment
     depth nesting-limit nesting-message)
  (let ((character (%edit-char text position limit)))
    (let ((node
            (cond
              ((and character
                    (member character +toml-quote-characters+ :test #'char=))
               (%make-edit-node :path-reversed path-reversed
                                :start position
                                :end (%edit-scan-string text position limit)
                                :kind :value
                                :children nil
                                :assignment assignment))
              ((and character
                    (member character '(#\[ #\{) :test #'char=))
               (let ((container-depth (1+ depth)))
                 (when (> container-depth nesting-limit)
                   (%edit-fail (reverse path-reversed) "~A" nesting-message))
                 (if (char= character #\[)
                     (%edit-scan-array-node
                      text position limit path-reversed assignment container-depth
                      nesting-limit nesting-message)
                     (%edit-scan-inline-node
                      text position limit path-reversed assignment container-depth
                      nesting-limit nesting-message))))
              (t
               (%edit-scan-scalar-node
                text position limit path-reversed assignment)))))
      (setf (edit-node-parent-depth node) depth)
      node)))
