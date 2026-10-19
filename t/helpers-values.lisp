(in-package #:cl-toml-kit/test)

(defun toml-test-value= (left right)
  (cond
    ((and (hash-table-p left) (hash-table-p right))
     (and (= (hash-table-count left) (hash-table-count right))
          (loop for key being the hash-keys of left
                always (multiple-value-bind (value present) (gethash key right)
                         (and present
                              (toml-test-value= (gethash key left) value))))))
    ((and (stringp left) (stringp right))
     (string= left right))
    ((and (floatp left) (floatp right))
     (sb-int:with-float-traps-masked (:invalid)
       (if (sb-ext:float-nan-p left)
           (sb-ext:float-nan-p right)
           (= left right))))
    ((and (toml-false-p left) (toml-false-p right)) t)
    ((and (cl-date-kit:offset-date-time-p left)
          (cl-date-kit:offset-date-time-p right))
     (string= (cl-date-kit:format-offset-date-time left :profile :rfc3339)
              (cl-date-kit:format-offset-date-time right :profile :rfc3339)))
    ((and (cl-date-kit:local-date-time-p left)
          (cl-date-kit:local-date-time-p right))
     (string= (cl-date-kit:format-local-date-time left :profile :rfc3339)
              (cl-date-kit:format-local-date-time right :profile :rfc3339)))
    ((and (cl-date-kit:local-date-p left) (cl-date-kit:local-date-p right))
     (string= (cl-date-kit:format-local-date left)
              (cl-date-kit:format-local-date right)))
    ((and (cl-date-kit:local-time-p left) (cl-date-kit:local-time-p right))
     (string= (cl-date-kit:format-local-time left :profile :rfc3339)
              (cl-date-kit:format-local-time right :profile :rfc3339)))
    ((and (vectorp left) (vectorp right))
     (and (= (length left) (length right))
          (loop for index below (length left)
                always (toml-test-value= (aref left index) (aref right index)))))
    (t (equal left right))))

(defun toml-test-date-values ()
  (list (cl-date-kit:offset-date-time-of 2026 1 2 3 4 5)
        (cl-date-kit:local-date-time-of 2026 1 2 3 4 5)
        (cl-date-kit:local-date-of 2026 1 2)
        (cl-date-kit:local-time-of 3 4 5)))

(defun toml-test-value-generator
    (self
     &key
       (integer-min -1000)
       (integer-max 1000)
       (string-max-length 8)
       (strings (list "" "text" "日本語" (format nil "line~%text")))
       (additional-scalars nil)
       (array-max-length 3))
  (cl-weave:gen-one-of
   (cl-weave:gen-one-of
    (cl-weave:gen-integer :min integer-min :max integer-max)
    (cl-weave:gen-string :max-length string-max-length)
    (cl-weave:gen-member strings)
    (cl-weave:gen-member
     (append (list t +toml-false+ 1.5d0 -0.0d0)
             additional-scalars)))
   (cl-weave:gen-member (toml-test-date-values))
   (cl-weave:gen-map
    (lambda (item)
      (let ((table (make-hash-table :test (function equal))))
        (setf (gethash "child" table) item)
        table))
    self)
   (cl-weave:gen-vector self :min-length 0 :max-length array-max-length)
   (cl-weave:gen-map
    (lambda (items)
      (make-array (length items) :initial-contents items))
    (cl-weave:gen-vector
     (cl-weave:gen-map
      (lambda (item)
        (let ((table (make-hash-table :test (function equal))))
          (setf (gethash "item" table) item)
          table))
      self)
     :min-length 1 :max-length array-max-length))))

(defun toml-test-document-generator (value-generator &optional (key "value"))
  (cl-weave:gen-map
   (lambda (value)
     (let ((document (make-hash-table :test (function equal))))
       (setf (gethash key document) value)
       document))
   value-generator))
