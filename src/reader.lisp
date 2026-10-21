;;;; src/reader.lisp
(in-package #:cl-toml-kit)

(defun %source-string (source source-name)
  (multiple-value-bind (limit message)
      (%toml-limit :input-characters)
    (flet ((input-limit-error (input position)
             (let* ((window-start (max 0 (- position 20)))
                    (window-end (min (length input) (+ position 20)))
                    (window (subseq input window-start window-end)))
               (error
                (make-toml-parse-error
                 :source-name source-name
                 :position position
                 :line nil
                 :column nil
                 :expected message
                 :text window)))))
      (etypecase source
        (string
         (when (> (length source) limit)
           (input-limit-error source limit))
         (coerce source 'simple-string))
        (stream
         (let ((text (make-array 256 :element-type 'character
                                 :adjustable t :fill-pointer 0)))
           (loop for char = (read-char source nil nil)
                 while char
                 do (when (= (fill-pointer text) limit)
                      (input-limit-error text limit))
                    (vector-push-extend char text))
           (coerce text 'simple-string)))))))

(defun parse (source &key source-name)
  (let* ((text (%source-string source source-name))
         (allowed-control-characters (cons #\Tab +toml-newline-characters+))
         (root (make-hash-table :test #'equal))
         (state (%make-reader-state :source text :source-name source-name
                                    :length (length text) :root root)))
    (setf (gethash root (toml-reader-state-table-depths state)) 0)
    (loop for index below (length text)
          for char = (char text index)
          for code = (char-code char)
          do (cond
               ((and (char= char +toml-carriage-return+)
                     (or (= (1+ index) (length text))
                         (not (char= (char text (1+ index)) +toml-line-feed+))))
                (%error-at state index :lf-after-cr))
               ((<= +toml-unicode-surrogate-start+ code
                    +toml-unicode-surrogate-end+)
                (%error-at state index :unicode-scalar-value))
               ((and (or (< code #x20) (= code #x7F))
                     (not (member char allowed-control-characters :test #'char=)))
                (%error-at state index :printable-character))))
    (flet ((finish-document (value position)
             (declare (ignore position))
             (%finalize-value value))
           (fail-document (position expected path)
             (%error-at state position expected path)))
      (declare (dynamic-extent #'finish-document #'fail-document))
      (toml-read-document state 0 #'finish-document #'fail-document))))

(defun %byte-position-line-column (bytes position &optional (start 0))
  (let ((text (cl-codec-kit:octets-to-string bytes
                                              :encoding :utf-8
                                              :start start
                                              :end position))
        (line 1)
        (column 1))
    (loop with index = 0
          while (< index (length text))
          do (let ((current-character (char text index)))
               (incf index)
               (cond
                 ((char= current-character +toml-carriage-return+)
                  (when (and (< index (length text))
                             (char= (char text index) +toml-line-feed+))
                    (incf index))
                  (incf line)
                  (setf column 1))
                 ((char= current-character +toml-line-feed+)
                  (incf line)
                  (setf column 1))
                 (t (incf column)))))
    (values line column)))

(defun %utf8-bom-length (bytes)
  (let ((bom-length (length +toml-utf8-bom+)))
    (if (and (>= (length bytes) bom-length)
             (equalp (subseq bytes 0 bom-length) +toml-utf8-bom+))
        bom-length
        0)))

(defun %decode-utf8 (bytes pathname)
  (let ((start (%utf8-bom-length bytes)))
    (handler-case
        (cl-codec-kit:octets-to-string bytes :encoding :utf-8 :start start)
      (cl-codec-kit:decode-error (condition)
        (let ((position (cl-codec-kit:decode-error-position condition)))
          (multiple-value-bind (line column)
              (%byte-position-line-column bytes position start)
            (error
             (make-toml-parse-error
              :source-name (namestring pathname)
              :position position :line line :column column
              :expected "UTF-8"))))))))

(defun parse-file (pathname)
  (let ((source-name (namestring pathname)))
    (with-open-file (stream pathname :direction :input
                            :element-type '(unsigned-byte 8))
      (multiple-value-bind (byte-limit byte-message)
          (%toml-limit :input-bytes)
        (labels ((input-limit-error ()
                   (error
                    (make-toml-parse-error
                     :source-name source-name
                     :position 0
                     :line nil
                     :column nil
                     :expected byte-message))))
          (let ((byte-length (file-length stream)))
            (when (and (integerp byte-length) (> byte-length byte-limit))
              (input-limit-error))
            (let ((bytes
                   (make-array (min 65536 (1+ byte-limit))
                               :element-type '(unsigned-byte 8)
                               :adjustable t :fill-pointer 0)))
              (loop
                for start = (fill-pointer bytes)
                for read-end = (min (1+ byte-limit) (+ start 65536))
                do (when (> read-end (array-total-size bytes))
                     (adjust-array
                      bytes
                      (min (1+ byte-limit)
                           (max read-end (* 2 (array-total-size bytes))))
                      :fill-pointer start))
                   (setf (fill-pointer bytes) read-end)
                   (let ((end (read-sequence bytes stream
                                             :start start :end read-end)))
                     (setf (fill-pointer bytes) end)
                     (when (> end byte-limit)
                       (input-limit-error))
                     (when (< end read-end)
                       (return))))
              (parse (%decode-utf8 bytes pathname)
                     :source-name source-name))))))))
