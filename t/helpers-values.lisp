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
           (and (= left right)
                (or (not (zerop left))
                    (= (float-sign left) (float-sign right)))))))
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
    ((and (vectorp left) (vectorp right)
          (not (stringp left))
          (not (stringp right)))
     (and (= (length left) (length right))
          (loop for index below (length left)
                always (toml-test-value= (aref left index) (aref right index)))))
    (t (equal left right))))

(defun toml-test-date-values ()
  (list (cl-date-kit:offset-date-time-of 2026 1 2 3 4 5)
        (cl-date-kit:local-date-time-of 2026 1 2 3 4 5)
        (cl-date-kit:local-date-of 2026 1 2)
        (cl-date-kit:local-time-of 3 4 5)))
(defun toml-test-string-alphabet ()
  (coerce
   (append
    (loop for code from 0 to 127
          unless (member code '(9 34 92))
            collect (code-char code))
    (list #\" #\\ #\Tab #\あ #\🧪))
   'string))
(defun toml-test-key-generator ()
  (cl-weave:gen-one-of
   (cl-weave:gen-string
    :min-length 1
    :max-length 12
    :alphabet (toml-test-string-alphabet))
   (cl-weave:gen-member
    '("plain" "key with spaces" "quoted\"key" "back\\slash" "日本語" "emoji 🧪"))))
(defun %toml-test-date-components-generator ()
  (cl-weave:gen-tuple
   (cl-weave:gen-member '(:offset-date-time :local-date-time :local-date :local-time))
   (cl-weave:gen-integer :min 2000 :max 2030)
   (cl-weave:gen-integer :min 1 :max 12)
   (cl-weave:gen-integer :min 1 :max 28)
   (cl-weave:gen-integer :min 0 :max 23)
   (cl-weave:gen-integer :min 0 :max 59)
   (cl-weave:gen-integer :min 0 :max 59)))
(defun toml-test-date-generator ()
  (cl-weave:gen-map
   (lambda (components)
     (destructuring-bind (kind year month day hour minute second) components
       (ecase kind
         (:offset-date-time
          (cl-date-kit:offset-date-time-of
           year month day hour minute second 0 (cl-date-kit:zone-offset-utc)))
         (:local-date-time
          (cl-date-kit:local-date-time-of
           year month day hour minute second))
         (:local-date
          (cl-date-kit:local-date-of year month day))
         (:local-time
          (cl-date-kit:local-time-of hour minute second)))))
   (%toml-test-date-components-generator)))

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
    (cl-weave:gen-string
     :max-length string-max-length
     :alphabet (toml-test-string-alphabet))
    (cl-weave:gen-member strings)
    (cl-weave:gen-member
     (append (list t +toml-false+ 1.5d0 -0.0d0)
             additional-scalars)))
   (toml-test-date-generator)
   (cl-weave:gen-map
    (lambda (pair)
      (destructuring-bind (key item) pair
        (let ((table (make-hash-table :test (function equal))))
          (setf (gethash key table) item)
          table)))
    (cl-weave:gen-tuple (toml-test-key-generator) self))
   (cl-weave:gen-vector self :min-length 0 :max-length array-max-length)
   (cl-weave:gen-map
    (lambda (items)
      (make-array (length items) :initial-contents items))
    (cl-weave:gen-vector
     (cl-weave:gen-map
      (lambda (pair)
        (destructuring-bind (key item) pair
          (let ((table (make-hash-table :test (function equal))))
            (setf (gethash key table) item)
            table)))
      (cl-weave:gen-tuple (toml-test-key-generator) self))
     :min-length 1 :max-length array-max-length))))

(defun toml-test-document-generator
    (value-generator &key (key-generator (toml-test-key-generator)))
  (cl-weave:gen-map
   (lambda (pair)
     (destructuring-bind (key value) pair
       (let ((document (make-hash-table :test (function equal))))
         (setf (gethash key document) value)
         document)))
   (cl-weave:gen-tuple key-generator value-generator)))
(defun %toml-test-table (&rest entries)
  (let ((table (make-hash-table :test (function equal))))
    (loop for (key value) on entries by (function cddr)
          do (setf (gethash key table) value))
    table))
(defun toml-test-parser-document-generator ()
  (cl-weave:gen-map
   (lambda (numbers)
     (let* ((inline
             (%toml-test-table
              "enabled" t
              "count" (aref numbers 1)
              "nested" (%toml-test-table "label" "inline")))
            (servers
             (vector
              (%toml-test-table
               "name" "alpha" "port" (aref numbers 2))
              (%toml-test-table
               "name" "beta" "port" (aref numbers 3))))
            (expected
             (%toml-test-table
              "positive" (aref numbers 0)
              "hex" #xDEADBEEF
              "octal" #o12345
              "binary" #b10101111
              "underscored" 1234567
              "escaped-quote"
              (concatenate 'string "quote: " (string #\"))
              "escaped-backslash"
              (concatenate 'string "slash: " (string #\\))
              "escaped-bmp" "あ"
              "escaped-scalar" "🧪"
              "positive-infinity" sb-ext:double-float-positive-infinity
              "nan" (sb-kernel:make-double-float #x7ff80000 0)
              "negative-zero" -0.0d0
              "date" (cl-date-kit:local-date-of 2026 1 2)
              "time" (cl-date-kit:local-time-of 3 4 5)
              "local-datetime"
              (cl-date-kit:local-date-time-of 2026 1 2 3 4 5)
              "offset-datetime"
              (cl-date-kit:offset-date-time-of
               2026 1 2 3 4 5 0 (cl-date-kit:zone-offset-utc))
              "inline" inline
              "servers" servers))
            (source
             (let ((quote-mark (string #\"))
                   (backslash-mark (string #\\)))
               (with-output-to-string (stream)
                 (format stream
                         "positive = +~D~%hex = 0xDEAD_BEEF~%octal = 0o12_345~%binary = 0b1010_1111~%underscored = 1_234_567~%"
                         (aref numbers 0))
                 (write-line
                  (concatenate 'string
                               "escaped-quote = " quote-mark "quote: "
                               backslash-mark quote-mark quote-mark)
                  stream)
                 (write-line
                  (concatenate 'string
                               "escaped-backslash = " quote-mark "slash: "
                               backslash-mark backslash-mark quote-mark)
                  stream)
                 (write-line
                  (concatenate 'string "escaped-bmp = " quote-mark
                               backslash-mark "u3042" quote-mark)
                  stream)
                 (write-line
                  (concatenate 'string "escaped-scalar = " quote-mark
                               backslash-mark "U0001F9EA" quote-mark)
                  stream)
                 (format stream
                         "positive-infinity = inf~%nan = nan~%negative-zero = -0.0~%date = 2026-01-02~%time = 03:04:05~%local-datetime = 2026-01-02T03:04:05~%offset-datetime = 2026-01-02T03:04:05Z~%")
                 (format stream
                         "inline = { enabled = true, count = ~D, nested = { label = \"inline\" } }~%"
                         (aref numbers 1))
                 (format stream "[[servers]]~%name = \"alpha\"~%port = ~D~%~%"
                         (aref numbers 2))
                 (format stream "[[servers]]~%name = \"beta\"~%port = ~D~%"
                         (aref numbers 3))))))
       (list source expected)))
   (cl-weave:gen-vector
    (cl-weave:gen-integer :min 1 :max 999999)
    :min-length 4 :max-length 4)))
