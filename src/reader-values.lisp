;;;; src/reader-values.lisp
(in-package #:cl-toml-kit)

(defun %skip-inline-space (state position)
  (loop
   (setf position (%skip-space-and-comments-at state position))
   (let ((char (%source-char state position)))
     (if (and char (member char +toml-newline-characters+ :test #'char=))
         (setf position (%skip-line-ending-at state position))
       (return position)))))

(define-toml-rule toml-read-value (state position success failure)
  (let* ((source (toml-reader-state-source state))
         (char (%source-char state position)))
    (cond
      ((and char (member char +toml-quote-characters+ :test #'char=))
       (%read-string-at state position success failure))
      ((eql char #\[)
       (toml-read-array state position success failure))
      ((eql char #\{)
       (toml-read-inline-table state position success failure))
      (t
       (let ((end (%scan-value-end state position)))
         (cond
           ((%token-equal-p source position end "true")
            (funcall success t end))
           ((%token-equal-p source position end "false")
            (funcall success +toml-false+ end))
           ((%date-shaped-p source position end)
            (%parse-date-value state position end success failure))
           ((%float-token-p source position end)
            (%parse-float-range state position end success failure))
           ((loop for token in +toml-positive-infinity-tokens+
                  thereis (%token-equal-p source position end token))
            (funcall success sb-ext:double-float-positive-infinity end))
           ((%token-equal-p source position end
                            +toml-negative-infinity-token+)
            (funcall success sb-ext:double-float-negative-infinity end))
           ((loop for token in +toml-nan-tokens+
                  thereis (%token-equal-p source position end token))
            (funcall success +toml-nan+ end))
           (t (%parse-integer-range state position end success failure))))))))

(define-toml-rule toml-read-array (state position success failure)
  (multiple-value-bind (nesting-limit nesting-message)
      (%toml-limit :nesting-depth)
    (let ((depth (1+ (toml-reader-state-nesting-depth state))))
      (when (> depth nesting-limit)
        (%error-at-message state position nesting-message nil t))
      (setf (toml-reader-state-nesting-depth state) depth)
      (let ((index (1+ position))
            (values '()))
        (loop
          (setf index (%skip-inline-space state index))
          (when (eql (%source-char state index) #\])
            (decf (toml-reader-state-nesting-depth state))
            (return-from toml-read-array
              (funcall success (coerce (nreverse values) 'simple-vector)
                       (1+ index))))
          (flet ((accept-element (value next)
                   (push value values)
                   (setf index (%skip-inline-space state next))
                   (cond
                     ((eql (%source-char state index) #\,)
                      (incf index))
                     ((eql (%source-char state index) #\])
                      nil)
                     (t
                      (funcall failure index
                               :comma-or-closing-bracket nil)))))
            (declare (dynamic-extent #'accept-element))
            (toml-read-value state index #'accept-element failure)))))))

(defun %inline-table-target
    (state table keys created error-position success failure)
  (let ((target table)
        (components (%path-parent keys)))
    (loop while components
          do (multiple-value-bind (key rest) (%path-next components)
               (setf components rest)
               (multiple-value-bind (child present) (gethash key target)
                 (cond
                   ((not present)
                    (setf child (make-hash-table :test #'equal)
                          (gethash key target) child
                          (gethash child
                                   (toml-reader-state-table-states state))
                          :inline
                          (gethash child created) t))
                   ((not (hash-table-p child))
                    (funcall failure error-position :inline-table nil))
                   ((and (eq (gethash
                              child
                              (toml-reader-state-table-states state))
                             :inline)
                         (not (gethash child created)))
                    (funcall failure error-position :inline-table nil)))
                 (setf target child))))
    (funcall success target)))

(defun %store-inline-value
    (state table keys created value error-position success failure)
  (flet ((store-in-target (target)
           (let ((key (%path-last keys)))
             (when (nth-value 1 (gethash key target))
               (funcall failure error-position :unique-inline-key nil))
             (setf (gethash key target) value)
             (funcall success))))
    (declare (dynamic-extent #'store-in-target))
    (%inline-table-target state table keys created error-position
                          #'store-in-target failure)))

(define-toml-rule toml-read-inline-table (state position success failure)
  (multiple-value-bind (nesting-limit nesting-message)
      (%toml-limit :nesting-depth)
    (let ((depth (1+ (toml-reader-state-nesting-depth state))))
      (when (> depth nesting-limit)
        (%error-at-message state position nesting-message nil t))
      (setf (toml-reader-state-nesting-depth state) depth)
      (let ((table (make-hash-table :test #'equal))
            (index (1+ position))
            (created (make-hash-table :test #'eq)))
        (loop
          (setf index (%skip-inline-space state index))
          (when (eql (%source-char state index) #\})
            (setf (gethash table
                           (toml-reader-state-table-states state))
                  :inline)
            (decf (toml-reader-state-nesting-depth state))
            (return-from toml-read-inline-table
              (funcall success table (1+ index))))
          (flet ((accept-inline-key (keys key-end)
                   (let ((equals-position (%skip-inline-space state key-end)))
                     (unless (eql (%source-char state equals-position) #\=)
                       (funcall failure equals-position :equals nil))
                     (let ((value-position
                             (%skip-inline-space state (1+ equals-position))))
                       (flet ((accept-inline-value (value value-end)
                                (flet ((inline-value-stored ()
                                         (setf index
                                               (%skip-inline-space
                                                state value-end))
                                         (cond
                                           ((eql (%source-char state index) #\,)
                                            (incf index))
                                           ((eql (%source-char state index) #\})
                                            nil)
                                           (t
                                            (funcall
                                             failure index
                                             :comma-or-closing-brace nil)))))
                                  (declare
                                   (dynamic-extent #'inline-value-stored))
                                  (%store-inline-value
                                   state table keys created value value-end
                                   #'inline-value-stored failure))))
                         (declare (dynamic-extent #'accept-inline-value))
                         (toml-read-value state value-position
                                          #'accept-inline-value failure))))))
            (declare (dynamic-extent #'accept-inline-key))
            (%read-key-path state index
                            #'accept-inline-key failure)))))))
