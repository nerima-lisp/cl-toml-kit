;;;; src/reader.lisp
(in-package #:cl-toml-kit)

(defun %source-string (source)
  (etypecase source
    (string (coerce source 'simple-string))
    (stream (let ((text (make-array 256 :element-type 'character :adjustable t :fill-pointer 0)))
              (loop for char = (read-char source nil nil)
                    while char do (vector-push-extend char text))
              (coerce text 'simple-string)))))

(defun parse (source &key source-name)
  (let* ((text (%source-string source))
         (root (make-hash-table :test #'equal))
         (state (%make-reader-state :source text :source-name source-name
                                    :length (length text) :root root)))
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
                 ((char= current-character #\Return)
                  (when (and (< index (length text))
                             (char= (char text index) #\Newline))
                    (incf index))
                  (incf line)
                  (setf column 1))
                 ((char= current-character #\Newline)
                  (incf line)
                  (setf column 1))
                 (t (incf column)))))
    (values line column)))

(defun %decode-utf8 (bytes pathname)
  (handler-case
      (cl-codec-kit:octets-to-string bytes :encoding :utf-8)
    (cl-codec-kit:decode-error (condition)
      (let ((position (cl-codec-kit:decode-error-position condition)))
        (multiple-value-bind (line column)
            (%byte-position-line-column bytes position)
          (error
           (make-toml-parse-error
            :source-name (namestring pathname)
            :position position :line line :column column
            :expected "UTF-8")))))))

(defun parse-file (pathname)
  (with-open-file (stream pathname :direction :input :element-type '(unsigned-byte 8))
    (let ((bytes (make-array (file-length stream) :element-type '(unsigned-byte 8))))
      (read-sequence bytes stream)
      (parse (%decode-utf8 bytes pathname) :source-name (namestring pathname)))))
