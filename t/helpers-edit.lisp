(in-package #:cl-toml-kit/test)

(defun %toml-test-format-text (text)
  (with-output-to-string (stream)
    (loop with start = 0
          for marker = (search "~%" text :start2 start)
          do (if marker
                 (progn
                   (write-string text stream :start start :end marker)
                   (write-char #\Newline stream)
                   (setf start (+ marker 2)))
                 (progn
                   (write-string text stream :start start)
                   (return))))))

(defun %toml-test-value-at-path (document path)
  (dolist (component path document)
    (setf document
          (if (integerp component)
              (aref document component)
              (gethash component document)))))

(defmacro it-edit-table (description cases)
  `(cl-weave:it-each
     ,cases
     ,description
     (source path value expected-text expected-value)
     (let* ((source-octets
              (sb-ext:string-to-octets (%toml-test-format-text source)
                                       :external-format :utf-8))
            (result-octets (edit-toml source-octets path value))
            (actual-text (sb-ext:octets-to-string result-octets
                                                   :external-format :utf-8))
            (actual-value (%toml-test-value-at-path (parse actual-text) path)))
       (cl-weave:expect
        (string= (%toml-test-format-text expected-text) actual-text))
       (cl-weave:expect
        (toml-test-value= expected-value actual-value)))))

(defun %edit-test-bytes (text)
  (sb-ext:string-to-octets (%toml-test-format-text text) :external-format :utf-8))

(defun %edit-test-text (bytes)
  (sb-ext:octets-to-string bytes :external-format :utf-8))

(defun %edit-test-parse (bytes)
  (let ((start (if (and (>= (length bytes) 3)
                        (= (aref bytes 0) 239)
                        (= (aref bytes 1) 187)
                        (= (aref bytes 2) 191))
                   3 0)))
    (parse (sb-ext:octets-to-string (subseq bytes start)
                                    :external-format :utf-8))))

(defun %edit-test-value (bytes path)
  (%toml-test-value-at-path (%edit-test-parse bytes) path))
