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
(defun %reader-path-depth-step (state table depth key)
  (if (null table)
      (values nil (1+ depth))
      (multiple-value-bind (child present) (gethash key table)
        (cond
          ((and present (hash-table-p child))
           (values child
                   (gethash child
                            (toml-reader-state-table-depths state)
                            (1+ depth))))
          ((and present (vectorp child) (plusp (length child))
                (hash-table-p (aref child (1- (length child)))))
           (let ((child-table (aref child (1- (length child)))))
             (values child-table
                     (gethash child-table
                              (toml-reader-state-table-depths state)
                              (+ depth 2)))))
          (t
           (values nil (1+ depth)))))))

(defun %read-key-path (state position success failure
                       &key depth-table (terminal-depth 0))
  (multiple-value-bind (limit message)
      (%toml-limit :nesting-depth)
    (let ((keys nil)
          (keys-tail nil)
          (table-cursor depth-table)
          (component-depth (%reader-path-depth state depth-table nil))
          (component-position position)
          (index position))
      (labels ((accept-key (key next)
                 (when (and (> (1+ component-depth) limit)
                            (eql (%source-char
                                  state
                                  (%skip-space-and-comments-at state next))
                                 #\.))
                   (%error-at-message state component-position message keys))
                 (let ((cell (list key)))
                   (if keys-tail
                       (setf (cdr keys-tail) cell)
                       (setf keys cell))
                   (setf keys-tail cell
                         index next))
                 (when (eql (%source-char
                             state (%skip-space-and-comments-at state next))
                            #\.)
                   (multiple-value-setq (table-cursor component-depth)
                     (%reader-path-depth-step state table-cursor
                                              component-depth key))))
               (component-followed-by-dot-p (position)
                 (let ((reader-position (toml-reader-state-position state)))
                   (unwind-protect
                        (let* ((position (%skip-space-and-comments-at state position))
                               (char (%source-char state position)))
                          (cond
                            ((and char (toml-bare-key-character-p char))
                             (let ((end (%scan-bare-key-end state position)))
                               (eql (%source-char
                                     state
                                     (%skip-space-and-comments-at state end))
                                    #\.)))
                            ((and char
                                  (member char +toml-quote-characters+ :test (function char=)))
                             (unless (and (eql (%source-char state (1+ position)) char)
                                          (eql (%source-char state (+ position 2)) char))
                               (let ((end (%simple-string-end state position char)))
                                 (and end
                                      (eql (%source-char
                                            state
                                            (%skip-space-and-comments-at
                                             state (1+ end)))
                                           #\.)))))
                            (t nil)))
                     (setf (toml-reader-state-position state) reader-position))))
               (read-key ()
                 (setf component-position
                       (%skip-space-and-comments-at state index))
                 (when (> (+ component-depth terminal-depth) limit)
                   (%error-at-message state component-position message keys))
                 (when (and (> (1+ component-depth) limit)
                            (component-followed-by-dot-p component-position))
                   (%error-at-message state component-position message keys))
                 (%read-key-component state component-position
                                      (function accept-key) failure)))
        (declare (dynamic-extent (function accept-key)
                                 (function component-followed-by-dot-p)
                                 (function read-key)))
        (read-key)
        (loop
          (setf index (%skip-space-and-comments-at state index))
          (unless (eql (%source-char state index) #\.)
            (return
              (funcall success
                       (if (cdr keys) keys (car keys))
                       index)))
          (incf index)
          (read-key))))))

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
             (if dotted :dotted :implicit)
             (gethash value (toml-reader-state-table-depths state))
             (1+ (%reader-path-depth state table nil))))
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
(defun %reader-path-depth (state table path)
  (let ((depth (if table
                   (gethash table
                            (toml-reader-state-table-depths state)
                            (toml-reader-state-nesting-depth state))
                   0))
        (components path))
    (loop while components
          do (multiple-value-bind (key rest) (%path-next components)
               (setf components rest)
               (multiple-value-setq (table depth)
                 (%reader-path-depth-step state table depth key))))
    depth))

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
  (let* ((root (toml-reader-state-root state))
         (parent-path (%path-parent path))
         (parent-depth (%reader-path-depth state root parent-path))
         (depth (+ parent-depth (if array-p 2 1))))
    (multiple-value-bind (limit message)
        (%toml-limit :nesting-depth)
      (when (> depth limit)
        (%error-at-message state position message path)))
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
                             :explicit
                             (gethash table
                                      (toml-reader-state-table-depths state))
                             (+ (%reader-path-depth state parent nil) 2))
                       (setf (toml-reader-state-current state) table)))
                   (let ((table (gethash key parent)))
                     (cond
                       ((null table)
                        (setf table (make-hash-table :test #'equal)
                              (gethash key parent) table
                              (gethash table
                                       (toml-reader-state-table-states state))
                              :explicit
                              (gethash table
                                       (toml-reader-state-table-depths state))
                              (1+ (%reader-path-depth state parent nil))))
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
      (%table-for-path state parent-path #'define-in-parent failure
                       :create t))))

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
                    #'accept-key-path failure
                    :depth-table (toml-reader-state-root state)
                    :terminal-depth (if array-p 2 1))))

(defun %read-document-assignment-line (state position success failure)
  (flet ((accept-key-path (path key-end)
           (let ((equals-position (%skip-space-and-comments-at state key-end)))
             (unless (eql (%source-char state equals-position) #\=)
               (funcall failure equals-position :equals path))
             (let ((value-position
                     (%skip-space-and-comments-at state (1+ equals-position))))
               (%read-document-assignment-value
                state path value-position success failure)))))
    (declare (dynamic-extent #'accept-key-path))
    (%read-key-path state position #'accept-key-path failure
                    :depth-table (or (toml-reader-state-current state)
                                     (toml-reader-state-root state)))))
(defun %read-document-assignment-value (state path value-position success failure)
  (let* ((base (or (toml-reader-state-current state)
                   (toml-reader-state-root state)))
         (depth (%reader-path-depth state base (%path-parent path))))
    (multiple-value-bind (limit message)
        (%toml-limit :nesting-depth)
      (when (> depth limit)
        (%error-at-message state value-position message path)))
    (let ((previous-depth (toml-reader-state-nesting-depth state)))
      (setf (toml-reader-state-nesting-depth state) depth)
      (unwind-protect
           (flet ((accept-value (value next)
                    (flet ((assignment-defined (ignored)
                             (declare (ignore ignored))
                             (let ((end (%skip-space-and-comments-at state next)))
                               (unless (let ((char (%source-char state end)))
                                         (or (null char)
                                             (member char +toml-newline-characters+
                                                     :test (function char=))))
                                 (funcall failure end :line-end path))
                               (funcall success nil
                                        (%skip-line-ending-at state end)))))
                      (declare (dynamic-extent (function assignment-defined)))
                      (%define-assignment state path value
                                          (function assignment-defined) failure))))
             (declare (dynamic-extent (function accept-value)))
             (toml-read-value state value-position
                              (function accept-value) failure))
        (setf (toml-reader-state-nesting-depth state) previous-depth)))))

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
  (let ((result value)
        (pending (make-array 48 :adjustable t :fill-pointer 0)))
    (flet ((push-frame (item parent key)
             (vector-push-extend item pending)
             (vector-push-extend parent pending)
             (vector-push-extend key pending))
           (pop-frame ()
             (let ((frame (vector-pop pending)))
               (setf (aref pending (fill-pointer pending)) nil)
               frame)))
      (declare (dynamic-extent (function push-frame)
                               (function pop-frame)))
      (push-frame value nil nil)
      (loop while (plusp (fill-pointer pending))
            do (let* ((key (pop-frame))
                      (parent (pop-frame))
                      (item (pop-frame))
                      (adjustable-vector-p
                        (and (vectorp item) (adjustable-array-p item)))
                      (finalized
                        (if adjustable-vector-p
                            (map (quote simple-vector)
                                 (function identity) item)
                            item)))
                 (cond
                   ((null parent)
                    (setf result finalized))
                   ((hash-table-p parent)
                    (setf (gethash key parent) finalized))
                   (t
                    (setf (aref parent key) finalized)))
                 (cond
                   ((hash-table-p finalized)
                    (flet ((queue-child (child-key child)
                             (when (or (hash-table-p child)
                                       (and (vectorp child)
                                            (adjustable-array-p child)))
                               (push-frame child finalized child-key))))
                      (declare (dynamic-extent (function queue-child)))
                      (maphash (function queue-child) finalized)))
                   (adjustable-vector-p
                    (loop for index downfrom (1- (length item)) to 0
                          for child = (aref item index)
                          when (or (hash-table-p child)
                                   (and (vectorp child)
                                        (adjustable-array-p child)))
                            do (push-frame child finalized index)))))))
    result))
