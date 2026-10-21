;;;; src/reader-scan.lisp
(in-package #:cl-toml-kit)

(defun %source-char (state position)
  (declare (type toml-reader-state state) (type fixnum position))
  (when (< position (toml-reader-state-length state))
    (char (toml-reader-state-source state) position)))

(defun %advance-to (state position)
  (declare (type toml-reader-state state) (type fixnum position))
  (loop while (< (toml-reader-state-position state) position)
        do (let ((char (%source-char state (toml-reader-state-position state))))
             (incf (toml-reader-state-position state))
             (when (and (char= char +toml-carriage-return+)
                        (eql (%source-char state (toml-reader-state-position state))
                             +toml-line-feed+))
               (incf (toml-reader-state-position state))))))

(defun %error-at-message (state position message &optional path)
  (let* ((source (toml-reader-state-source state))
         (end (min (length source) (+ position 40)))
         (span (cl-parser-kit:make-span :source source :start position :end end))
         (diagnostic (cl-parser-kit:make-diagnostic :message message :span span))
         (text (cl-parser-kit:diagnostic->string diagnostic))
         (line 1)
         (column 1))
    (loop with index = 0
          while (< index position)
          do (let ((char (char source index)))
               (incf index)
               (cond
                 ((char= char +toml-carriage-return+)
                  (when (and (< index position)
                             (char= (char source index) +toml-line-feed+))
                    (incf index))
                  (incf line)
                  (setf column 1))
                 ((char= char +toml-line-feed+)
                  (incf line)
                  (setf column 1))
                 (t
                  (incf column)))))
    (error
     (make-toml-parse-error
      :source-name (toml-reader-state-source-name state)
      :position position :line line :column column :path path
      :expected message :context "TOML" :text text))))

(defun %error-at (state position expected-key &optional (path nil))
  (%error-at-message state position
                     (%toml-reader-error-message expected-key)
                     path))
(defun %toml-limit-error-message (key)
  (if (eq key :table-count)
      "TOML table count limit exceeded"
      (%toml-limit-base-error-message key)))
(defun %toml-limit (key)
  (if (eq key :table-count)
      (let ((value *toml-max-tables*))
        (check-type value (integer 0 *))
        (values (min value +toml-max-tables-ceiling+)
                (%toml-limit-error-message key)))
      (%toml-limit-base key)))
(defun %reader-make-table
    (state &optional (position (toml-reader-state-position state)))
  (multiple-value-bind (limit message) (%toml-limit :table-count)
    (when (>= (hash-table-count
               (toml-reader-state-table-depths state))
              limit)
      (%error-at-message state position message))
    (make-hash-table :test #'equal)))

(defun %skip-space-and-comments (state)
  (loop
    (loop while (toml-space-character-p (%source-char state (toml-reader-state-position state)))
          do (%advance-to state (1+ (toml-reader-state-position state))))
    (if (eql (%source-char state (toml-reader-state-position state)) #\#)
        (loop for char = (%source-char state (toml-reader-state-position state))
              while (and char (not (member char +toml-newline-characters+ :test #'char=)))
              do (%advance-to state (1+ (toml-reader-state-position state))))
        (return))))

(defun %skip-line-ending (state)
  (let ((char (%source-char state (toml-reader-state-position state))))
    (when (and char (member char +toml-newline-characters+ :test #'char=))
      (%advance-to state (1+ (toml-reader-state-position state))))))

(defun %skip-line-ending-at (state position)
  (%advance-to state position)
  (%skip-line-ending state)
  (toml-reader-state-position state))

(defun %skip-space-and-comments-at (state position)
  (%advance-to state position)
  (%skip-space-and-comments state)
  (toml-reader-state-position state))

(defun %scan-bare-key-end (state position)
  (loop while (toml-bare-key-character-p (%source-char state position))
        do (incf position)
        finally (return position)))

(defun %scan-atom-end (state position)
  (loop while (let ((char (%source-char state position)))
                (and char
                     (not (or (toml-space-character-p char)
                              (%toml-value-terminator-p char)))))
        do (incf position)
        finally (return position)))

(defun %scan-value-end (state position)
  (let ((end (%scan-atom-end state position)))
    (if (and (= (- end position) 10)
             (eq (%toml-date-separator-kind (%source-char state (+ position 4))) :date)
             (toml-space-character-p (%source-char state end))
             (toml-decimal-character-p (%source-char state (1+ end)))
             (toml-decimal-character-p (%source-char state (+ end 2)))
             (eq (%toml-date-separator-kind (%source-char state (+ end 3))) :time))
        (%scan-atom-end state (1+ end))
        end)))
