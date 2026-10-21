;;;; Format-preserving editing of UTF-8 TOML byte vectors.
(in-package #:cl-toml-kit)

(declaim
  (ftype function
    %edit-apply-edit-range
    %edit-existing-edit-range
    %edit-addition-range))

(defun %edit-validate-result (original path new-value delete-p result)
  (let ((expected (%edit-copy-value original)))
    (%edit-semantic-change expected path new-value delete-p)
    (handler-case
        (multiple-value-bind (text offset) (%edit-octets-to-string result)
          (declare (ignore offset))
          (let ((actual (parse text)))
            (unless (%edit-value-equal-p expected actual)
              (%edit-fail path
                          "The edited TOML parses to a different value than requested"))
            result))
      (error (condition)
        (%edit-fail path "The edited bytes are not valid TOML: ~A" condition)))))

(defun %edit-build-result
    (source text positions assignments sections path new-value delete-p
     &key (path-prefix-p #'%edit-path-prefix-p))
  (let ((matches (%edit-collect-nodes assignments path)))
    (when (> (length matches) 1)
      (%edit-fail path "The path identifies more than one source value"))
    (cond
      ((plusp (length matches))
       (let ((match (first matches)))
         (%edit-apply-edit-range
          source positions
          (%edit-existing-edit-range text (car match) (cdr match)
                                     path new-value delete-p))))
      (delete-p
       (%edit-fail path "The path does not identify an existing value"))
      (t
       (%edit-apply-edit-range
        source positions
        (%edit-addition-range
         text assignments sections path new-value
         :path-prefix-p path-prefix-p))))))

(defun %edit-toml
    (source path new-value new-value-p delete-p
     &key
       (array-table-counter-path #'%edit-array-table-counter-path)
       (path-prefix-p #'%edit-path-prefix-p))
  (unless (and (vectorp source) (not (stringp source)))
    (error 'type-error :datum source :expected-type '(vector (unsigned-byte 8))))
  (multiple-value-bind (byte-limit byte-message)
      (%toml-limit :input-bytes)
    (when (> (length source) byte-limit)
      (%edit-fail nil "~A" byte-message)))
  (unless (%edit-byte-elements-p source)
    (error 'type-error :datum source :expected-type '(vector (unsigned-byte 8))))
  (let ((normalized-path (%edit-normalize-path path)))
    (when (and (not new-value-p) (not delete-p))
      (%edit-fail normalized-path "An edit value or delete request is required"))
    (multiple-value-bind (text bom-offset) (%edit-octets-to-string source)
      (multiple-value-bind (character-limit character-message)
          (%toml-limit :input-characters)
        (when (> (length text) character-limit)
          (%edit-fail nil "~A" character-message)))
      (let ((original (parse text)))
        (multiple-value-bind (assignments sections)
            (%edit-scan-document
             text :array-table-counter-path array-table-counter-path)
          (let* ((positions (%edit-byte-positions text bom-offset))
                 (result
                   (%edit-build-result
                    source text positions assignments sections normalized-path
                    new-value delete-p :path-prefix-p path-prefix-p)))
            (%edit-validate-result
             original normalized-path new-value delete-p result)))))))

(defun edit-toml
    (source path &optional (new-value nil new-value-p) &key delete)
  "Edit a UTF-8 TOML byte vector while retaining all unrelated source bytes.

PATH is a string or a sequence of string keys and non-negative array indices.
Use :DELETE T, or call DELETE-TOML, to remove an existing value."
  (%edit-toml source path new-value new-value-p delete))

(defun delete-toml (source path)
  "Delete the value at PATH from a UTF-8 TOML byte vector."
  (edit-toml source path nil :delete t))

(defun %edit-apply-edit-range (source positions range)
  (%edit-apply-bytes
   source
   (list (%edit-replacement positions (first range) (second range)
                             (third range)))))

(defun %edit-existing-edit-range (text node parent path new-value delete-p)
  (let ((range (if delete-p
                   (%edit-delete-range text node parent)
                   (list (edit-node-start node) (edit-node-end node)
                         (%edit-value-bytes-for-node text node new-value)))))
    (when (and delete-p
               (%edit-deletion-has-comment-p text (first range) (second range)))
      (%edit-fail path "Deletion would remove or strand a comment"))
    range))

(defun %edit-ambiguous-parent-p
    (assignments sections parent-path
     &key (path-prefix-p #'%edit-path-prefix-p))
  (or (some #'integerp parent-path)
      (some (lambda (assignment)
              (let ((path (edit-assignment-path assignment)))
                (and (< (length parent-path) (length path))
                     (funcall path-prefix-p parent-path path))))
            assignments)
      (some (lambda (section)
              (let ((path (edit-section-path section)))
                (and path (funcall path-prefix-p parent-path path))))
            sections)))

(defun %edit-array-addition-p (last-component parent-match)
  (and (integerp last-component)
       parent-match
       (eq (edit-node-kind (car parent-match)) :array)
       (= last-component
          (length (edit-node-children (car parent-match))))))

(defun %edit-inline-addition-p (last-component parent-match)
  (and (stringp last-component)
       parent-match
       (eq (edit-node-kind (car parent-match)) :inline)))

(defun %edit-unambiguous-root-addition-p
    (last-component assignments sections parent-path
     &key (path-prefix-p #'%edit-path-prefix-p))
  (and (stringp last-component)
       (not (%edit-ambiguous-parent-p
             assignments sections parent-path :path-prefix-p path-prefix-p))))

(defun %edit-addition-range
    (text assignments sections path new-value
     &key (path-prefix-p #'%edit-path-prefix-p))
  (let* ((last-component (car (last path)))
         (parent-path (butlast path))
         (parent-match (first (%edit-collect-nodes assignments parent-path)))
         (parent-node (car parent-match))
         (array-addition-p (%edit-array-addition-p last-component parent-match))
         (inline-addition-p (%edit-inline-addition-p last-component parent-match))
         (initial-depth (if (or array-addition-p inline-addition-p)
                            (1+ (edit-node-parent-depth parent-node))
                          0))
         (value (%edit-value-bytes new-value initial-depth path))
         (section (%edit-section-for-path sections parent-path))
         (writer-path (%edit-path-vector parent-path)))
    (labels ((validate-key (key)
               (%validate-writer-key key writer-path))
             (validate-key-path (key-path)
               (let ((key-path-vector (%edit-path-vector nil)))
                 (dolist (key key-path)
                   (%validate-writer-key key key-path-vector)
                   (vector-push-extend key key-path-vector)))))
      (cond
        (array-addition-p
         (%edit-insert-array text parent-node value))
        (inline-addition-p
         (validate-key last-component)
         (%edit-insert-inline text parent-node last-component value))
        ((and (stringp last-component) section)
         (validate-key last-component)
         (%edit-insert-line text section (list last-component) value))
        ((%edit-unambiguous-root-addition-p
          last-component assignments sections parent-path
          :path-prefix-p path-prefix-p)
         (validate-key-path path)
         (%edit-insert-line text (or (%edit-section-for-path sections nil)
                                     (first sections))
                            path value))
        (t
         (%edit-fail path
                     "Adding this path would require an ambiguous table or array structure"))))))
