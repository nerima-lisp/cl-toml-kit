(in-package #:cl-toml-kit)

(defun %read-string-at (state position success failure)
  (let* ((quote (%source-char state position))
         (triple (and (eql (%source-char state (1+ position)) quote)
                      (eql (%source-char state (+ position 2)) quote)))
         (index (+ position (if triple 3 1))))
    (unless triple
      (let ((close (%simple-string-end state position quote)))
        (when close
          (funcall success
                   (subseq (toml-reader-state-source state) (1+ position) close)
                   (1+ close))
          (return-from %read-string-at nil))))
    (%buffer-reset state)
    (when (and triple
               (member (%source-char state index) +toml-newline-characters+))
      (%advance-to state (1+ index))
      (setf index (toml-reader-state-position state)))
    (loop
     (when (>= index (toml-reader-state-length state))
       (funcall failure
                index
                :closing-string-delimiter
                nil)
       (return-from %read-string-at nil))
     (when (%read-string-closer state index quote triple success failure)
       (return-from %read-string-at nil))
     (let ((next (%read-string-character state index quote triple failure)))
       (unless next
         (return-from %read-string-at nil))
       (setf index next)))))

(defun %read-string-closer (state index quote triple success failure)
  (let ((char (%source-char state index)))
    (cond
     ((and triple (char= char quote)
           (eql (%source-char state (1+ index)) quote)
           (eql (%source-char state (+ index 2)) quote))
      (let ((count 3))
        (loop while (eql (%source-char state (+ index count)) quote)
              do (incf count))
        (if (> count 5)
            (funcall failure index :multiline-string-delimiter nil)
          (progn
            (dotimes (ignored (- count 3))
              (declare (ignore ignored))
              (%buffer-char state quote))
            (funcall success (%finish-buffer state) (+ index count))))
        t))
     ((and (not triple) (char= char quote))
      (funcall success (%finish-buffer state) (1+ index))
      t)
     (t nil))))

(defun %read-string-character (state index quote triple failure)
  (let ((char (%source-char state index)))
    (cond
     ((and (char= quote #\") (char= char #\\))
      (let ((continuation
             (and triple (%multiline-string-continuation-end state index))))
        (or continuation
            (let ((escaped (%read-string-escape-at state index failure)))
              (when escaped
                (%buffer-char state (car escaped))
                (cdr escaped))))))
     ((and (not triple)
           (member char +toml-newline-characters+ :test #'char=))
      (funcall failure index :single-line-string nil))
     ((and (toml-control-character-p char)
           (not (char= char #\Tab))
           (not triple))
      (funcall failure index :printable-string-character nil))
     ((and (char= quote #\') (char= char +toml-carriage-return+))
      (funcall failure index :literal-string-character nil))
     (t
      (%buffer-char state char)
      (1+ index)))))

(defun %multiline-string-continuation-end (state index)
  (let ((continuation (1+ index)))
    (loop while (toml-space-character-p (%source-char state continuation))
          do (incf continuation))
    (when (member (%source-char state continuation) +toml-newline-characters+)
      (let ((position (%skip-line-ending-at state continuation)))
        (loop
         (loop while (toml-space-character-p (%source-char state position))
               do (incf position))
         (if (member (%source-char state position) +toml-newline-characters+)
             (setf position (%skip-line-ending-at state position))
           (return position)))))))

(defun %read-string-escape-at (state index failure)
  (block decoded-escape
    (%read-escape state index
                  (lambda (value next)
                    (return-from decoded-escape (cons value next)))
                  failure)))

(defun %simple-string-end (state position quote)
  (let ((source (toml-reader-state-source state))
        (index (1+ position))
        (length (toml-reader-state-length state)))
    (loop while (< index length)
          for char = (char source index)
          do (cond
              ((char= char quote)
               (return-from %simple-string-end index))
              ((or (and (char= quote #\") (char= char #\\))
                   (member char +toml-newline-characters+ :test #'char=)
                   (and (toml-control-character-p char)
                        (not (char= char #\Tab))))
               (return-from %simple-string-end nil))
              (t (incf index)))
          finally (return nil))))

(defun %read-escape (state position success failure)
  (let* ((char (%source-char state (1+ position)))
         (index (and char (position char +toml-escape-letters+ :test #'char=)))
         (width (%toml-hex-escape-width char)))
    (cond
     (index
      (funcall success (aref +toml-escape-table+ index) (+ position 2)))
     (width
      (let ((value 0))
        (loop for offset below width
              for digit = (%toml-hex-digit-value
                           (%source-char state (+ position 2 offset)))
              do (unless digit
                   (funcall failure (+ position 2 offset) :hex-digit nil)
                   (return-from %read-escape nil))
              (setf value (+ (* value 16) digit)))
        (unless (and (<= value +toml-unicode-scalar-max+)
                     (or (< value +toml-unicode-surrogate-start+)
                         (> value +toml-unicode-surrogate-end+)))
          (funcall failure position :unicode-scalar-value nil)
          (return-from %read-escape nil))
        (let ((decoded (code-char value)))
          (unless decoded
            (funcall failure position :unicode-scalar-value nil)
            (return-from %read-escape nil))
          (funcall success decoded (+ position 2 width)))))
     (t
      (funcall failure position :valid-escape-sequence nil)))))

(defun %finish-buffer (state)
  (coerce (toml-reader-state-buffer state) 'simple-string))

(defun %buffer-char (state char)
  (vector-push-extend char (toml-reader-state-buffer state)))

(defun %buffer-reset (state)
  (setf (fill-pointer (toml-reader-state-buffer state)) 0))
