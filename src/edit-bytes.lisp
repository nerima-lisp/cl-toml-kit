(in-package #:cl-toml-kit)

(declaim
  (ftype function
    %edit-string-value-bytes-for-node
    %edit-triple-string-p
    %edit-reject-invalid-literal-string
    %edit-literal-string-value
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
    (loop for index below (length text)
          do (setf (aref positions (1+ index))
                   (+ (aref positions index)
                      (cl-codec-kit:string-size-in-octets
                       text :start index :end (1+ index) :encoding :utf-8))))
    positions))

(defun %edit-string-to-bytes (text)
  (cl-codec-kit:string-to-octets text :encoding :utf-8))

(defun %edit-value-bytes (value)
  (with-output-to-string (stream)
    (%write-value value stream (make-array 8 :adjustable t :fill-pointer 0))))

(defun %edit-value-bytes-for-node (text node value)
  (if (not (stringp value))
      (%edit-value-bytes value)
      (%edit-string-value-bytes-for-node text node value)))

(defun %edit-string-value-bytes-for-node (text node value)
  (let* ((start (edit-node-start node))
         (delimiter (char text start))
         (triple (%edit-triple-string-p text start node delimiter)))
    (if (char= delimiter #\')
        (progn
          (%edit-reject-invalid-literal-string node value triple)
          (%edit-literal-string-value value triple))
        (%edit-basic-string-value value triple))))

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

(defun %edit-literal-string-value (value triple)
  (if triple
      (format nil "'''~A'''" value)
      (format nil "'~A'" value)))

(defun %edit-basic-string-value (value triple)
  (let* ((encoded (%edit-value-bytes value))
         (length (length encoded)))
    (if triple
        (format nil "\"\"\"~A\"\"\""
                (subseq encoded 1 (1- length)))
        encoded)))
