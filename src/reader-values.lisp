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
  (let ((index (1+ position)) (values '()))
    (loop
      (setf index (%skip-inline-space state index))
      (when (eql (%source-char state index) #\])
        (funcall success (coerce (nreverse values) 'simple-vector)
                 (1+ index))
        (return-from toml-read-array nil))
      (let ((element
              (block parsed-element
                (toml-read-value
                 state index
                 (lambda (value next)
                   (return-from parsed-element (cons value next)))
                 failure))))
        (unless element (return-from toml-read-array nil))
        (push (car element) values)
        (setf index (cdr element))
        (setf index (%skip-inline-space state index))
        (cond
          ((eql (%source-char state index) #\,)
           (incf index))
          ((eql (%source-char state index) #\])
           nil)
          (t
           (funcall failure index :comma-or-closing-bracket nil)
           (return-from toml-read-array nil)))))))

(defun %inline-table-target (state table keys created error-position failure)
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
                         :inline)
                   (push child created))
                  ((not (hash-table-p child))
                   (funcall failure error-position :inline-table nil)
                   (return-from %inline-table-target nil))
                  ((and (eq (gethash
                             child
                             (toml-reader-state-table-states state))
                            :inline)
                        (not (member child created :test #'eq)))
                   (funcall failure error-position :inline-table nil)
                   (return-from %inline-table-target nil)))
                 (setf target child))))
    target))

(defun %store-inline-value (state table keys created value error-position failure)
  (let ((target (%inline-table-target
                 state table keys created error-position failure)))
    (unless target (return-from %store-inline-value nil))
    (let ((key (%path-last keys)))
      (when (nth-value 1 (gethash key target))
        (funcall failure error-position :unique-inline-key nil)
        (return-from %store-inline-value nil))
      (setf (gethash key target) value)
      t)))

(defun %read-inline-pair (state position table created success failure)
  (let ((key-result
         (block parsed-key
           (%read-key-path
            state position
            (lambda (keys next)
              (return-from parsed-key (cons keys next)))
            failure))))
    (unless key-result (return-from %read-inline-pair nil))
    (let* ((keys (car key-result))
           (equals-position
            (%skip-inline-space state (cdr key-result))))
      (unless (eql (%source-char state equals-position) #\=)
        (funcall failure equals-position :equals nil)
        (return-from %read-inline-pair nil))
      (let ((value-position
             (%skip-inline-space state (1+ equals-position))))
        (toml-read-value
         state value-position
         (lambda (value value-end)
           (unless (%store-inline-value
                    state table keys created value value-end failure)
             (return-from %read-inline-pair nil))
           (funcall success value value-end))
         failure)))))

(define-toml-rule toml-read-inline-table (state position success failure)
  (let ((table (make-hash-table :test #'equal))
        (index (1+ position))
        (created '()))
    (loop
      (setf index (%skip-inline-space state index))
      (when (eql (%source-char state index) #\})
        (setf (gethash table (toml-reader-state-table-states state)) :inline)
        (funcall success table (1+ index))
        (return-from toml-read-inline-table nil))
      (let ((next
              (block next-pair
                (%read-inline-pair
                 state index table created
                 (lambda (value value-end)
                   (declare (ignore value))
                   (return-from next-pair value-end))
                 failure))))
        (unless next (return-from toml-read-inline-table nil))
        (setf index (%skip-inline-space state next))
        (cond
          ((eql (%source-char state index) #\,)
           (incf index))
          ((eql (%source-char state index) #\})
           nil)
          (t
           (funcall failure index :comma-or-closing-brace nil)
           (return-from toml-read-inline-table nil)))))))
