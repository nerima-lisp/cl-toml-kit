;;;; src/reader-document.lisp
(in-package #:cl-toml-kit)

(defun %read-key-component (state position success failure)
  (declare (dynamic-extent success failure))
  (let* ((position (%skip-space-and-comments-at state position))
         (char (%source-char state position)))
    (cond
      ((member char +toml-quote-characters+)
       (if (and (eql (%source-char state (1+ position)) char)
                (eql (%source-char state (+ position 2)) char))
           (funcall failure position :single-line-key nil)
           (%read-string-at state position success failure)))
      ((toml-bare-key-character-p char)
       (let ((end (%scan-bare-key-end state position)))
         (funcall success
                  (subseq (toml-reader-state-source state) position end)
                  end)))
      (t (funcall failure position :key nil)))))

(defun %read-key-path (state position success failure)
  (declare (dynamic-extent success failure))
  (labels ((fail (error-position expected path)
             (return-from %read-key-path
               (funcall failure error-position expected path))))
    (declare (dynamic-extent (function fail)))
    (let* ((first
             (block first-component
               (flet ((accept-key (key next)
                        (return-from first-component (cons key next))))
                 (declare (dynamic-extent (function accept-key)))
                 (%read-key-component state position #'accept-key #'fail))))
           (keys (list (car first)))
           (index (cdr first)))
      (loop
        (setf index (%skip-space-and-comments-at state index))
        (unless (eql (%source-char state index) #\.)
          (return (funcall success
                           (if (cdr keys) (nreverse keys) (car keys))
                           index)))
        (setf index (1+ index))
        (let ((component
                (block next-component
                  (flet ((accept-key (key next)
                           (return-from next-component (cons key next))))
                    (declare (dynamic-extent (function accept-key)))
                    (%read-key-component state index #'accept-key #'fail)))))
          (push (car component) keys)
          (setf index (cdr component)))))))

(defun %table-for-path-component (state table key path create dotted failure)
  (declare (dynamic-extent failure))
  (multiple-value-bind (value present) (gethash key table)
    (cond
      ((not present)
       (unless create
         (return-from %table-for-path-component
           (funcall failure (toml-reader-state-position state)
                    :defined-table path)))
       (setf value (make-hash-table :test #'equal)
             (gethash key table) value
             (gethash value (toml-reader-state-table-states state))
             (if dotted :dotted :implicit)))
      ((hash-table-p value)
       (when (or (eq (gethash value (toml-reader-state-table-states state))
                     :inline)
                 (and dotted
                      (eq (gethash value (toml-reader-state-table-states state))
                          :explicit)))
         (return-from %table-for-path-component
           (funcall failure (toml-reader-state-position state)
                    :defined-table path))))
      ((and (vectorp value) (> (length value) 0)
            (hash-table-p (aref value (1- (length value)))))
       (if dotted
           (return-from %table-for-path-component
             (funcall failure (toml-reader-state-position state) :table path))
           (setf value (aref value (1- (length value)))))
       (when (eq (gethash value (toml-reader-state-table-states state)) :inline)
         (return-from %table-for-path-component
           (funcall failure (toml-reader-state-position state)
                    :inline-table path))))
      (t
       (return-from %table-for-path-component
         (funcall failure (toml-reader-state-position state) :table path))))
    value))

(defun %table-for-path (state path &key (create nil) (dotted nil) base failure)
  (labels ((fail (error-position expected error-path)
             (return-from %table-for-path
               (funcall failure error-position expected error-path))))
    (let ((table (or base (toml-reader-state-root state)))
          (components path))
      (loop while components
            do (multiple-value-bind (key rest) (%path-next components)
                 (setf components rest)
                 (setf table (%table-for-path-component
                              state table key path create dotted #'fail))))
      table)))

(defun %define-assignment (state path value failure)
  (declare (dynamic-extent failure))
  (let* ((base (or (toml-reader-state-current state)
                   (toml-reader-state-root state)))
         (parent (%table-for-path state (%path-parent path) :create t
                                  :dotted (> (%path-length path) 1)
                                  :base base :failure failure))
         (key (%path-last path)))
    (multiple-value-bind (old present) (gethash key parent)
      (declare (ignore old))
      (when present
        (return-from %define-assignment
          (funcall failure (toml-reader-state-position state) :unique-key path))))
    (setf (gethash key parent) value)
    (when (hash-table-p value)
      (setf (gethash value (toml-reader-state-table-states state)) :inline))))

(defun %read-header-end (state position array-p path success failure)
  (declare (dynamic-extent success failure))
  (let ((index (%skip-space-and-comments-at state position)))
    (unless (eql (%source-char state index) #\])
      (return-from %read-header-end
        (funcall failure index :closing-bracket path)))
    (incf index)
    (when (and array-p (not (eql (%source-char state index) #\])))
      (return-from %read-header-end
        (funcall failure index :closing-array-table-delimiter path)))
    (when array-p (incf index))
    (setf index (%skip-space-and-comments-at state index))
    (unless (let ((char (%source-char state index)))
              (or (null char)
                  (member char +toml-newline-characters+)))
      (return-from %read-header-end (funcall failure index :line-end path)))
    (funcall success nil index)))

(defun %define-header-table (state position path array-p failure)
  (declare (dynamic-extent failure))
  (let ((parent (%table-for-path state (%path-parent path) :create t
                                 :failure failure))
        (key (%path-last path)))
    (if array-p
        (let ((value (gethash key parent)))
          (when (and value (vectorp value) (zerop (length value)))
            (return-from %define-header-table
              (funcall failure position :array-table path)))
          (when (and value (not (vectorp value)))
            (return-from %define-header-table
              (funcall failure position :array-table path)))
          (unless value
            (setf value (make-array 0 :adjustable t :fill-pointer 0)
                  (gethash key parent) value))
          (let ((table (make-hash-table :test #'equal)))
            (vector-push-extend table value)
            (setf (gethash table (toml-reader-state-table-states state)) :explicit)
            (setf (toml-reader-state-current state) table)))
        (let ((table (gethash key parent)))
          (cond
            ((null table)
             (setf table (make-hash-table :test #'equal)
                   (gethash key parent) table
                   (gethash table (toml-reader-state-table-states state)) :explicit))
            ((not (hash-table-p table))
             (return-from %define-header-table
               (funcall failure position :table path)))
            ((member (gethash table (toml-reader-state-table-states state))
                     '(:explicit :dotted))
             (return-from %define-header-table
               (funcall failure position :unique-table path)))
            ((eq (gethash table (toml-reader-state-table-states state)) :inline)
             (return-from %define-header-table
               (funcall failure position :extendable-table path)))
            (t
             (setf (gethash table (toml-reader-state-table-states state)) :explicit)))
          (setf (toml-reader-state-current state) table)))))

(defun %read-header (state position array-p success failure)
  (declare (dynamic-extent success failure))
  (labels ((fail (error-position expected path)
             (return-from %read-header
               (funcall failure error-position expected path))))
    (%read-key-path
     state (+ position (if array-p 2 1))
     (lambda (path next)
       (%read-header-end
        state next array-p path
        (lambda (value end)
          (declare (ignore value))
          (%define-header-table state position path array-p #'fail)
          (setf (toml-reader-state-position state) end)
          (funcall success nil end))
        #'fail))
     #'fail)))

(defun %read-document-assignment-line (state position success failure)
  (declare (dynamic-extent success failure))
  (let* ((key-result
           (block key-path
             (flet ((accept-key-path (path next)
                      (return-from key-path (cons path next))))
               (declare (dynamic-extent (function accept-key-path)))
               (%read-key-path state position #'accept-key-path failure))))
         (path (car key-result))
         (equals-position
           (%skip-space-and-comments-at state (cdr key-result))))
    (unless (eql (%source-char state equals-position) #\=)
      (funcall failure equals-position :equals path))
    (let ((value-position
            (%skip-space-and-comments-at state (1+ equals-position))))
      (block parsed-value
        (flet ((accept-value (value next)
                 (%define-assignment state path value failure)
                 (let ((end (%skip-space-and-comments-at state next)))
                   (unless (let ((char (%source-char state end)))
                             (or (null char)
                                 (member char +toml-newline-characters+)))
                     (funcall failure end :line-end path))
                   (return-from parsed-value
                     (funcall success nil (%skip-line-ending-at state end))))))
          (declare (dynamic-extent (function accept-value)))
          (toml-read-value state value-position #'accept-value failure))))))

(define-toml-rule toml-read-document (state position success failure)
  (labels ((fail (error-position expected path)
             (return-from toml-read-document
               (funcall failure error-position expected path))))
    (declare (dynamic-extent (function fail)))
    (flet ((next-header-line (value next)
             (declare (ignore value))
             (%skip-line-ending-at state next))
           (next-assignment-line (value next)
             (declare (ignore value))
             next))
      (declare (dynamic-extent (function next-header-line) (function next-assignment-line)))
      (let ((index position))
        (loop
          (setf index (%skip-space-and-comments-at state index))
          (cond
            ((>= index (toml-reader-state-length state))
             (return (funcall success (toml-reader-state-root state) index)))
            ((member (%source-char state index) +toml-newline-characters+)
             (setf index (%skip-line-ending-at state index)))
            ((eql (%source-char state index) #\[)
             (let ((array-p (eql (%source-char state (1+ index)) #\[)))
               (setf index
                     (%read-header state index array-p
                                   #'next-header-line #'fail))))
            (t
             (setf index
                   (%read-document-assignment-line
                    state index #'next-assignment-line #'fail)))))))))

(defun %finalize-value (value)
  (cond
    ((and (vectorp value) (adjustable-array-p value))
     (map 'simple-vector #'%finalize-value value))
    ((hash-table-p value)
     (maphash (lambda (key item) (setf (gethash key value) (%finalize-value item))) value)
     value)
    (t value)))
