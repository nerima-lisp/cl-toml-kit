(in-package #:cl-toml-kit)

(declaim
  (ftype function
    %edit-string-value-bytes-for-node
    %edit-triple-string-p
    %edit-reject-invalid-literal-string
    %edit-basic-string-value))

(defun %edit-octets-to-string (bytes)
  (let ((offset (%utf8-bom-length bytes)))
    (handler-case
        (values (cl-codec-kit:octets-to-string bytes :encoding :utf-8 :start offset)
                offset)
      (cl-codec-kit:decode-error (condition)
        (let ((position (cl-codec-kit:decode-error-position condition)))
          (multiple-value-bind (line column)
              (%byte-position-line-column bytes position offset)
            (error (make-toml-parse-error :position position
                                          :line line :column column
                                          :expected "UTF-8" :text condition))))))))

(defun %edit-byte-positions (text offset)
  (let ((positions (make-array (1+ (length text)))))
    (setf (aref positions 0) offset)
    ;; Callers pass valid UTF-8 text; edit-toml uses %edit-octets-to-string.
    (loop with byte-position = offset
          for index below (length text)
          for code = (char-code (char text index))
          do (incf byte-position
                   (cond
                     ((<= code #x7f) 1)
                     ((<= code #x7ff) 2)
                     ((<= code #xffff) 3)
                     (t 4)))
             (setf (aref positions (1+ index)) byte-position))
    positions))

(defun %edit-string-to-bytes (text)
  (cl-codec-kit:string-to-octets text :encoding :utf-8))

(defun %edit-value-bytes (value &optional (initial-depth 0) path)
  (with-output-to-string (stream)
    (%with-writer-context initial-depth
      (%write-value
       value stream
       (make-array (length path)
                   :adjustable t
                   :fill-pointer t
                   :initial-contents path)))))

(defun %edit-value-bytes-for-node (text node value)
  (let ((path (edit-node-path node)))
    (if (stringp value)
        (%edit-string-value-bytes-for-node text node value path)
        (%edit-value-bytes value (edit-node-parent-depth node) path))))

(defun %edit-string-value-bytes-for-node (text node value path)
  (let* ((start (edit-node-start node))
         (delimiter (char text start))
         (triple (%edit-triple-string-p text start node delimiter)))
    (if (char= delimiter #\')
        (progn
          (%validate-toml-string
           value
           (make-array (length path)
                       :adjustable t
                       :fill-pointer t
                       :initial-contents path))
          (%edit-reject-invalid-literal-string node value triple)
          (if triple
              (format nil "'''~A'''" value)
              (format nil "'~A'" value)))
        (%edit-basic-string-value value triple path))))

(defun %edit-triple-string-p (text start node delimiter)
  (and (<= (+ start 2) (1- (edit-node-end node)))
       (char= delimiter (char text (1+ start)))
       (char= delimiter (char text (+ start 2)))))

(defun %edit-reject-invalid-literal-string (node value triple)
  (when (or (and (not triple)
                 (or (find #\' value)
                     (find #\Newline value)
                     (find #\Return value)))
            (and triple (search "'''" value)))
    (%edit-fail (edit-node-path node)
                "The replacement cannot retain the literal-string delimiter")))

(defun %edit-basic-string-value (value triple path)
  (let* ((encoded (%edit-value-bytes value 0 path))
         (length (length encoded)))
    (if triple
        (format nil "\"\"\"~A\"\"\""
                (subseq encoded 1 (1- length)))
        encoded)))
