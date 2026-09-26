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
                (error (make-toml-parse-error :source-name source-name
                                               :position index :expected "LF after CR")))
               ((and (or (< (char-code char) #x20) (= (char-code char) #x7F))
                     (not (member char '(#\Tab #\Newline #\Return))))
                (error (make-toml-parse-error :source-name source-name
                                               :position index :expected "printable character")))))
    (toml-read-document state 0 (lambda (value position)
                                  (declare (ignore position))
                                  (%finalize-value value)))))

(defun parse-file (pathname)
  (with-open-file (stream pathname :direction :input :element-type '(unsigned-byte 8))
    (let ((bytes (make-array (file-length stream) :element-type '(unsigned-byte 8))))
      (read-sequence bytes stream)
      (let ((text (handler-case
                      (sb-ext:octets-to-string bytes :external-format :utf-8)
                    (error ()
                      (error (make-toml-parse-error :source-name (namestring pathname)
                                                     :expected "UTF-8"))))))
        (parse text :source-name (namestring pathname))))))
