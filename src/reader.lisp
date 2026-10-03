;;;; src/reader.lisp
(in-package #:cl-toml-kit)

(defun %source-string (source)
  (etypecase source
    (string (coerce source 'simple-string))
    (stream (let ((text (make-array 256 :element-type 'character :adjustable t :fill-pointer 0)))
              (loop for char = (read-char source nil nil)
                    while char do (vector-push-extend char text))
              (coerce text 'simple-string)))))

(defun parse (source &key source-name (max-depth +toml-default-max-depth+))
  (%toml-max-depth max-depth)
  (let* ((text (%source-string source))
         (root (make-hash-table :test #'equal))
         (state (%make-reader-state :source text :source-name source-name
                                    :length (length text) :root root
                                    :max-depth max-depth)))
    (loop for index below (length text)
          for char = (char text index)
          do (cond
               ((and (char= char #\Return)
                     (or (= (1+ index) (length text))
                         (not (char= (char text (1+ index)) #\Newline))))
                (%error-at state index "LF after CR"))
               ((and (or (< (char-code char) #x20) (= (char-code char) #x7F))
                     (not (member char '(#\Tab #\Newline #\Return))))
                (%error-at state index "printable character"))))
    (toml-read-document state 0 (lambda (value position)
                                  (declare (ignore position))
                                  (%finalize-value value)))))

(defun %decoding-error-position (condition)
  (let ((text (princ-to-string condition))
        (prefix "byte position "))
    (when (search prefix text)
      (parse-integer text :start (+ (search prefix text) (length prefix))
                     :junk-allowed t))))

(defun %byte-position-line-column (bytes position)
  (let ((line 1)
        (column 1))
    (loop for index below position
          for byte = (aref bytes index)
          if (= byte #x0A)
            do (incf line) (setf column 1)
          else do (incf column))
    (values line column)))

(defun %decode-utf8 (bytes pathname)
  (handler-case
      (sb-ext:octets-to-string bytes :external-format :utf-8)
    (sb-int:character-decoding-error (condition)
      (let ((position (%decoding-error-position condition)))
        (multiple-value-bind (line column)
            (%byte-position-line-column bytes (or position 0))
          (error
           (make-toml-parse-error
            :source-name (namestring pathname)
            :position (or position 0) :line line :column column
            :expected "UTF-8")))))))

(defun parse-file (pathname &key (max-depth +toml-default-max-depth+))
  (with-open-file (stream pathname :direction :input :element-type '(unsigned-byte 8))
    (let ((bytes (make-array (file-length stream) :element-type '(unsigned-byte 8))))
      (read-sequence bytes stream)
      (parse (%decode-utf8 bytes pathname) :source-name (namestring pathname)
             :max-depth max-depth))))
