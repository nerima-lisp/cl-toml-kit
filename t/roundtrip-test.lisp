(in-package #:cl-toml-kit/test)

(defun %roundtrip-value= (left right)
  (cond
    ((and (hash-table-p left) (hash-table-p right))
     (and (= (hash-table-count left) (hash-table-count right))
          (loop for key being the hash-keys of left
                always (multiple-value-bind (value present) (gethash key right)
                         (and present (%roundtrip-value= (gethash key left) value))))))
    ((and (vectorp left) (vectorp right))
     (and (= (length left) (length right))
          (loop for index below (length left)
                always (%roundtrip-value= (aref left index) (aref right index)))))
    ((and (floatp left) (floatp right))
     (if (sb-ext:float-nan-p left) (sb-ext:float-nan-p right) (= left right)))
    ((and (toml-false-p left) (toml-false-p right)) t)
    ((and (or (cl-date-kit:offset-date-time-p left)
              (cl-date-kit:local-date-time-p left)
              (cl-date-kit:local-date-p left)
              (cl-date-kit:local-time-p left))
          (typep right (type-of left)))
     (string= (%reader-date-text left) (%reader-date-text right)))
    (t (equal left right))))

(defun %roundtrip-date-values ()
  (list (cl-date-kit:offset-date-time-of 2026 1 2 3 4 5)
        (cl-date-kit:local-date-time-of 2026 1 2 3 4 5)
        (cl-date-kit:local-date-of 2026 1 2)
        (cl-date-kit:local-time-of 3 4 5)))

(defun %roundtrip-generated-values (self)
  (gen-one-of
   (gen-one-of (gen-integer :min -100000 :max 100000)
               (gen-member (list "" "text" "日本語" "line\ntext"))
               (gen-member (list t +toml-false+ 0.1d0 -0.0d0
                                   1.0d308 least-positive-double-float)))
   (gen-member (%roundtrip-date-values))
   (gen-map (lambda (item) (let ((table (make-hash-table :test 'equal)))
                              (setf (gethash "child" table) item)
                              table))
            self)
   (cl-weave:gen-vector self :min-length 0 :max-length 3)
   (gen-map (lambda (items) (coerce items 'vector))
            (cl-weave:gen-vector
             (gen-map (lambda (item) (let ((table (make-hash-table :test 'equal)))
                                       (setf (gethash "item" table) item)
                                       table))
                      self)
             :min-length 1 :max-length 3))))

(defun %register-roundtrip-tests ()
  (let ((fixtures (getf (load-toml-fixtures) :valid)))
    ;; cl-weave v1.3.0 requires literal it-each cases, so runtime fixtures use EVAL.
    (eval `(it-each
             ,(mapcar (lambda (fixture)
                        (list (namestring (toml-fixture-toml fixture)))) fixtures)
             "round-trips valid TOML fixture ~A"
             (name)
             (let* ((first (parse-file (pathname name)))
                    (second (parse (encode first))))
               (expect (%roundtrip-value= first second)))))))

(it-property "preserves generated TOML values through encoding and parsing"
    ((value (gen-recursive
             (gen-one-of (gen-integer :min -1000 :max 1000)
                         (gen-member (list "text" "日本語" t +toml-false+ 1.5d0)))
             #'%roundtrip-generated-values
             :max-depth 4)))
  (let* ((table (let ((result (make-hash-table :test 'equal)))
                  (setf (gethash "value" result) value)
                  result))
         (decoded (parse (encode table))))
    (expect (%roundtrip-value= table decoded))))
