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
(defun %toml-test-nan-from-infinities (positive negative)
  (sb-int:with-float-traps-masked (:invalid)
    (+ positive negative)))

(defun %toml-test-nan ()
  (%toml-test-nan-from-infinities
   sb-ext:double-float-positive-infinity
   sb-ext:double-float-negative-infinity))

(defun %toml-test-group-digits (digits group-size)
  (with-output-to-string (stream)
    (loop for index below (length digits)
          do (when (and (plusp index)
                        (zerop (mod (- (length digits) index) group-size)))
               (write-char #\_ stream))
             (write-char (char digits index) stream))))

(defun %toml-test-basic-string-token (value)
  (with-output-to-string (stream)
    (write-char #\" stream)
    (loop for character across value
          for code = (char-code character)
          do (cond ((char= character #\") (write-string "\\\"" stream))
                   ((char= character #\\) (write-string "\\\\" stream))
                   ((= code 8) (write-string "\\b" stream))
                   ((= code 9) (write-string "\\t" stream))
                   ((= code 10) (write-string "\\n" stream))
                   ((= code 12) (write-string "\\f" stream))
                   ((= code 13) (write-string "\\r" stream))
                   ((or (< code 32) (<= 127 code 159))
                    (format stream "\\u~4,'0X" code))
                   (t (write-char character stream))))
    (write-char #\" stream)))

(defun %toml-test-escaped-string (suffix escape-characters)
  (concatenate 'string
               "quote:" (string #\")
               " slash:" (string #\\)
               (coerce escape-characters 'string)
               " " suffix))

(defun %toml-test-date-token (value)
  (cond ((cl-date-kit:offset-date-time-p value)
         (cl-date-kit:format-offset-date-time value :profile :rfc3339))
        ((cl-date-kit:local-date-time-p value)
         (cl-date-kit:format-local-date-time value :profile :rfc3339))
        ((cl-date-kit:local-date-p value)
         (cl-date-kit:format-local-date value))
        ((cl-date-kit:local-time-p value)
         (cl-date-kit:format-local-time value :profile :rfc3339))))

(defun %toml-test-source-document (components)
  (destructuring-bind
      (positive negative hexadecimal octal binary underscored group-size
       infinity-sign nan-sign negative-zero suffix escape-characters date
       inline-amount records)
      components
    (let* ((escaped-value
             (%toml-test-escaped-string suffix escape-characters))
           (dynamic-key
             (concatenate 'string "field:" suffix (string #\") (string #\\)))
           (inline-value
             (%toml-test-escaped-string
              (concatenate 'string suffix "!") escape-characters))
           (expected-records
             (map 'vector
                  (lambda (record)
                    (destructuring-bind (name rank) record
                      (%toml-test-table "name" name "rank" rank)))
                  records))
           (expected
             (apply #'%toml-test-table
                    (append
                     (list "plus" positive
                           "negative" (- negative)
                           "hex" hexadecimal
                           "octal" octal
                           "binary" binary
                           "underscored" underscored
                           "positive-infinity" sb-ext:double-float-positive-infinity
                           "negative-infinity" sb-ext:double-float-negative-infinity
                           "nan" (%toml-test-nan)
                           "negative-zero" (- 0d0)
                           "escaped" escaped-value
                           dynamic-key escaped-value
                           "date" date
                           "inline" (%toml-test-table
                                     "amount" inline-amount
                                     "label" inline-value)
                           "records" expected-records))))
           (source
             (with-output-to-string (stream)
               (flet ((grouped (value base)
                        (%toml-test-group-digits
                         (string-downcase
                          (write-to-string value :base base :radix nil))
                         group-size)))
                 (format stream "plus = +~A~%" (grouped positive 10))
                 (format stream "negative = -~A~%" (grouped negative 10))
                 (format stream "hex = 0x~A~%" (grouped hexadecimal 16))
                 (format stream "octal = 0o~A~%" (grouped octal 8))
                 (format stream "binary = 0b~A~%" (grouped binary 2))
                 (format stream "underscored = ~A~%" (grouped underscored 10))
                 (format stream
                         "positive-infinity = ~Ainf~%negative-infinity = -inf~%nan = ~Anan~%negative-zero = ~A~%"
                         infinity-sign nan-sign negative-zero)
                 (format stream "escaped = ~A~%~A = ~A~%"
                         (%toml-test-basic-string-token escaped-value)
                         (%toml-test-basic-string-token dynamic-key)
                         (%toml-test-basic-string-token escaped-value))
                 (format stream "date = ~A~%"
                         (%toml-test-date-token date))
                 (format stream "inline = { amount = ~A, label = ~A }~%"
                         (grouped inline-amount 10)
                         (%toml-test-basic-string-token inline-value))
                 (loop for record across records
                       do (destructuring-bind (name rank) record
                            (format stream
                                    "~%[[records]]~%name = ~A~%rank = ~D~%"
                                    (%toml-test-basic-string-token name) rank)))))))
      (list source expected))))

(defun toml-test-source-document-generator ()
  (cl-weave:gen-map
   #'%toml-test-source-document
   (cl-weave:gen-tuple
    (cl-weave:gen-integer :min 100000 :max 9999999)
    (cl-weave:gen-integer :min 1 :max 9999999)
    (cl-weave:gen-integer :min #x10000 :max #xFFFFFF)
    (cl-weave:gen-integer :min #o10000 :max #o777777)
    (cl-weave:gen-integer :min #b1000000000 :max #b1111111111111111)
    (cl-weave:gen-integer :min 10000 :max 9999999999)
    (cl-weave:gen-integer :min 2 :max 4)
    (cl-weave:gen-member '("" "+"))
    (cl-weave:gen-member '("" "+" "-"))
    (cl-weave:gen-member '("-0.0" "-0.00" "-0e0" "-0.0_0"))
    (cl-weave:gen-string :max-length 8
                         :alphabet (toml-test-string-alphabet))
    (cl-weave:gen-vector
     (cl-weave:gen-member
      (list (code-char 8) #\Tab #\Newline (code-char 12) #\Return
            (code-char 0) (code-char 127) #\" #\\
            (char "あ" 0) (char "🧪" 0)))
     :min-length 1 :max-length 8)
    (toml-test-date-generator)
    (cl-weave:gen-integer :min 1 :max 9999999)
    (cl-weave:gen-vector
     (cl-weave:gen-tuple
      (cl-weave:gen-string :min-length 1 :max-length 8
                           :alphabet (toml-test-string-alphabet))
      (cl-weave:gen-integer :min -999999 :max 999999))
     :min-length 1 :max-length 3))))
