;;;; src/reader-document.lisp
(in-package #:cl-toml-kit)

(defun %read-key-component (state position success failure)
  (let* ((position (%skip-space-and-comments-at state position))
         (char (%source-char state position)))
    (cond
      ((and char (member char +toml-quote-characters+ :test #'char=))
       (if (and (eql (%source-char state (1+ position)) char)
                (eql (%source-char state (+ position 2)) char))
           (funcall failure position :single-line-key nil)
           (%read-string-at state position success failure)))
      ((toml-bare-key-character-p char)
       (let ((end (%scan-bare-key-end state position)))
         (funcall success
                  (subseq (toml-reader-state-source state) position end)
                  end)))
      (t
       (funcall failure position :key nil)))))

(defun %read-key-path (state position success failure)
  (let ((keys nil)
        (index position))
    (flet ((accept-key (key next)
             (push key keys)
             (setf index next)))
      (declare (dynamic-extent #'accept-key))
      (%read-key-component state index #'accept-key failure)
      (loop
        (setf index (%skip-space-and-comments-at state index))
        (unless (eql (%source-char state index) #\.)
          (return
            (funcall success
                     (if (cdr keys) (nreverse keys) (car keys))
                     index)))
        (incf index)
        (%read-key-component state index #'accept-key failure)))))

(defun %table-for-path-component
    (state table key path create dotted success failure)
  (multiple-value-bind (value present) (gethash key table)
    (cond
      ((not present)
       (unless create
         (funcall failure (toml-reader-state-position state)
                  :defined-table path))
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
         (funcall failure (toml-reader-state-position state)
                  :defined-table path)))
      ((and (vectorp value) (> (length value) 0)
            (hash-table-p (aref value (1- (length value)))))
       (if dotted
           (funcall failure (toml-reader-state-position state) :table path)
           (setf value (aref value (1- (length value)))))
       (when (eq (gethash value (toml-reader-state-table-states state)) :inline)
         (funcall failure (toml-reader-state-position state)
                  :inline-table path)))
      (t
       (funcall failure (toml-reader-state-position state) :table path)))
    (funcall success value)))

(defun %table-for-path (state path success failure
                         &key (create nil) (dotted nil) base)
  (let ((table (or base (toml-reader-state-root state)))
        (components path))
    (flet ((accept-component (next-table)
             (setf table next-table)))
      (declare (dynamic-extent #'accept-component))
      (loop while components
            do (multiple-value-bind (key rest) (%path-next components)
                 (setf components rest)
                 (%table-for-path-component
                  state table key path create dotted
                  #'accept-component failure))))
    (funcall success table)))

(defun %define-assignment (state path value success failure)
  (let ((base (or (toml-reader-state-current state)
                  (toml-reader-state-root state))))
    (flet ((store-in-parent (parent)
             (let ((key (%path-last path)))
               (when (nth-value 1 (gethash key parent))
                 (funcall failure
                          (toml-reader-state-position state) :unique-key path))
               (setf (gethash key parent) value)
               (when (hash-table-p value)
                 (setf (gethash value
                                (toml-reader-state-table-states state))
                       :inline))
               (funcall success nil))))
      (declare (dynamic-extent #'store-in-parent))
      (%table-for-path state (%path-parent path) #'store-in-parent failure
                       :create t :dotted (> (%path-length path) 1)
                       :base base))))

(defun %read-header-end (state position array-p path success failure)
  (let ((index (%skip-space-and-comments-at state position)))
    (unless (eql (%source-char state index) #\])
      (funcall failure index :closing-bracket path))
    (incf index)
    (when (and array-p (not (eql (%source-char state index) #\])))
      (funcall failure index :closing-array-table-delimiter path))
    (when array-p (incf index))
    (setf index (%skip-space-and-comments-at state index))
    (unless (let ((char (%source-char state index)))
              (or (null char)
                  (member char +toml-newline-characters+ :test #'char=)))
      (funcall failure index :line-end path))
    (funcall success nil index)))

(defun %define-header-table (state position path array-p success failure)
  (flet ((define-in-parent (parent)
           (let ((key (%path-last path)))
             (if array-p
                 (let ((value (gethash key parent)))
                   (when (and value (vectorp value) (zerop (length value)))
                     (funcall failure position :array-table path))
                   (when (and value (not (vectorp value)))
                     (funcall failure position :array-table path))
                   (unless value
                     (setf value (make-array 0 :adjustable t :fill-pointer 0)
                           (gethash key parent) value))
                   (let ((table (make-hash-table :test #'equal)))
                     (vector-push-extend table value)
                     (setf (gethash table
                                    (toml-reader-state-table-states state))
                           :explicit)
                     (setf (toml-reader-state-current state) table)))
                 (let ((table (gethash key parent)))
                   (cond
                     ((null table)
                      (setf table (make-hash-table :test #'equal)
                            (gethash key parent) table
                            (gethash table
                                     (toml-reader-state-table-states state))
                            :explicit))
                     ((not (hash-table-p table))
                      (funcall failure position :table path))
                     ((member (gethash
                               table
                               (toml-reader-state-table-states state))
                              '(:explicit :dotted))
                      (funcall failure position :unique-table path))
                     ((eq (gethash table
                                   (toml-reader-state-table-states state))
                          :inline)
                      (funcall failure position :extendable-table path))
                     (t
                      (setf (gethash table
                                     (toml-reader-state-table-states state))
                            :explicit)))
                   (setf (toml-reader-state-current state) table)))
             (funcall success nil))))
    (declare (dynamic-extent #'define-in-parent))
    (%table-for-path state (%path-parent path) #'define-in-parent failure
                     :create t)))

(defun %read-header (state position array-p success failure)
  (flet ((accept-key-path (path next)
           (flet ((accept-header-end (value end)
                    (declare (ignore value))
                    (flet ((header-table-defined (ignored)
                             (declare (ignore ignored))
                             (funcall success nil end)))
                      (declare (dynamic-extent #'header-table-defined))
                      (%define-header-table state position path array-p
                                            #'header-table-defined failure))))
             (declare (dynamic-extent #'accept-header-end))
             (%read-header-end state next array-p path
                               #'accept-header-end failure))))
    (declare (dynamic-extent #'accept-key-path))
    (%read-key-path state (+ position (if array-p 2 1))
                    #'accept-key-path failure)))

(defun %read-document-assignment-line (state position success failure)
  (flet ((accept-key-path (path key-end)
           (let ((equals-position (%skip-space-and-comments-at state key-end)))
             (unless (eql (%source-char state equals-position) #\=)
               (funcall failure equals-position :equals path))
             (let ((value-position
                     (%skip-space-and-comments-at state (1+ equals-position))))
               (flet ((accept-value (value next)
                        (flet ((assignment-defined (ignored)
                                 (declare (ignore ignored))
                                 (let ((end (%skip-space-and-comments-at state next)))
                                   (unless (let ((char (%source-char state end)))
                                             (or (null char)
                                                 (member char +toml-newline-characters+
                                                         :test #'char=)))
                                     (funcall failure end :line-end path))
                                   (funcall success
                                            nil (%skip-line-ending-at state end)))))
                          (declare (dynamic-extent #'assignment-defined))
                          (%define-assignment state path value
                                              #'assignment-defined failure))))
                 (declare (dynamic-extent #'accept-value))
                 (toml-read-value state value-position #'accept-value failure))))))
    (declare (dynamic-extent #'accept-key-path))
    (%read-key-path state position #'accept-key-path failure)))

(define-toml-rule toml-read-document (state position success failure)
  (let ((index position))
    (flet ((next-header-line (value next)
             (declare (ignore value))
             (setf index (%skip-line-ending-at state next)))
           (next-assignment-line (value next)
             (declare (ignore value))
             (setf index next)))
      (declare (dynamic-extent #'next-header-line
                               #'next-assignment-line))
      (loop
        (setf index (%skip-space-and-comments-at state index))
        (cond
          ((>= index (toml-reader-state-length state))
           (return
             (funcall success (toml-reader-state-root state) index)))
          ((member (%source-char state index)
                   +toml-newline-characters+ :test #'char=)
           (setf index (%skip-line-ending-at state index)))
          ((eql (%source-char state index) #\[)
           (let ((array-p (eql (%source-char state (1+ index)) #\[)))
             (%read-header state index array-p #'next-header-line failure)))
          (t
           (%read-document-assignment-line
            state index #'next-assignment-line failure)))))))

(defun %finalize-value (value)
  (cond
    ((and (vectorp value) (adjustable-array-p value))
     (map 'simple-vector #'%finalize-value value))
    ((hash-table-p value)
     (maphash (lambda (key item) (setf (gethash key value) (%finalize-value item))) value)
     value)
    (t value)))
