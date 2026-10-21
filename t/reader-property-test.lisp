(in-package #:cl-toml-kit/test)
;; This timeout must beat cl-weave's timeout, which skips timed-out trials.
(defun %reader-property-run-with-fail-fast-timeout (description thunk)
  (handler-case
      (sb-ext:with-timeout 5
        (funcall thunk))
    (sb-ext:timeout ()
      (error "TOML parser fuzz trial timed out while ~A" description))
    ;; Fuzz inputs accept any public TOML kit error condition.
    (toml-kit-error () nil)
    (serious-condition (condition)
      (error "TOML parser fuzz trial ~A raised unexpected condition ~A: ~A"
             description (type-of condition) condition))))
(defun %reader-property-with-byte-file (octets thunk)
  (uiop:with-temporary-file (:stream stream :pathname pathname
                             :directory (uiop:temporary-directory)
                             :prefix "cl-toml-kit-reader-property-"
                             :element-type (quote (unsigned-byte 8)))
    (write-sequence octets stream)
    ;; UIOP closes the stream before it calls this thunk with the temporary path.
    :close-stream
    (funcall thunk pathname)))
(defun %reader-property-mutated-valid-toml-octets (value)
  (let* ((octets
           (%edit-test-bytes
            (format nil "value = ~D~%text = \"水\"~%" value)))
         (value-position
           (position-if (lambda (octet) (<= 48 octet 57)) octets))
         (digit (aref octets value-position)))
    (setf (aref octets value-position)
          (if (= digit 57) 56 (1+ digit)))
    octets))

(defun %reader-property-random-octets-generator ()
  (cl-weave:gen-map
   (lambda (bytes)
     (make-array (length bytes)
                 :element-type (quote (unsigned-byte 8))
                 :initial-contents bytes))
   (cl-weave:gen-vector
    (cl-weave:gen-integer :min 0 :max 255)
    :min-length 1024 :max-length 8192)))

(defun %reader-property-valid-mutated-octets-generator ()
  (cl-weave:gen-map
   #'%reader-property-mutated-valid-toml-octets
   (cl-weave:gen-integer :min 100 :max 999)))

(defun %reader-property-octets-generator ()
  (cl-weave:gen-one-of
   (%reader-property-random-octets-generator)
   (%reader-property-valid-mutated-octets-generator)))
(defun %reader-property-nested-source (kind depth)
  (ecase kind
    (:array
     (concatenate (quote string)
                  "value = "
                  (make-string depth :initial-element #\[)
                  "0"
                  (make-string depth :initial-element #\])))
    (:inline-table
     (concatenate
      (quote string)
      "value = "
      (with-output-to-string (stream)
        (dotimes (index depth)
          (write-string "{a = " stream))
        (write-char #\0 stream)
        (dotimes (index depth)
          (write-char #\} stream)))))))
(defun %reader-property-dotted-key-source (segment-count)
  (let ((key
          (with-output-to-string (stream)
            (write-char #\a stream)
            (dotimes (index (1- segment-count))
              (write-string ".a" stream)))))
    (format nil "~A = 0" key)))
;; Fuzz checks termination and condition class; parser properties check value semantics.
(describe "TOML parser generated input"
  (it-property "reads generated decimal integer documents"
      ((value (cl-weave:gen-integer
               :min -9223372036854775808
               :max 9223372036854775807)))
    (expect
     (toml-test-value=
      value
      (gethash "value"
               (parse (format nil "value = ~D" value))))))
  (cl-weave:it-fuzz
   "returns a value or signals a TOML kit error for long generated strings"
      ((source (cl-weave:gen-string
                :min-length 2048
                :max-length 32768
                :alphabet
                (concatenate
                 (quote string)
                 "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 #=[]{},.+-_:"
                 (map (quote string) (function code-char)
                      (quote (0 1 9 10 13 31 127 34 39 92)))))))
    (:trials 32 :timeout-per-trial 8)
    (%reader-property-run-with-fail-fast-timeout
     "parsing generated text"
     (lambda () (parse source))))
  (cl-weave:it-fuzz
   "returns a value or signals a TOML kit error for long nested arrays"
      ((depth (cl-weave:gen-integer :min 1024 :max 4096)))
    (:trials 8 :timeout-per-trial 8)
    (%reader-property-run-with-fail-fast-timeout
     "parsing nested arrays"
     (lambda () (parse (%reader-property-nested-source :array depth)))))
  (cl-weave:it-fuzz
   "returns a value or signals a TOML kit error for long nested inline tables"
      ((depth (cl-weave:gen-integer :min 1024 :max 4096)))
    (:trials 8 :timeout-per-trial 8)
    (%reader-property-run-with-fail-fast-timeout
     "parsing nested inline tables"
     (lambda ()
       (parse (%reader-property-nested-source :inline-table depth)))))
  (cl-weave:it-fuzz
   "returns a value or signals a TOML kit error for dotted keys at and beyond the depth limit"
      ((segment-count
        (cl-weave:gen-one-of
         (cl-weave:gen-member '(1024 1025 1026 2048 4096))
         (cl-weave:gen-integer :min 1024 :max 4096))))
    (:trials 8 :timeout-per-trial 8)
    (let ((*toml-max-nesting-depth* 1024))
      (%reader-property-run-with-fail-fast-timeout
       "parsing a dotted key at and beyond the depth limit"
       (lambda ()
         (parse (%reader-property-dotted-key-source segment-count))))))
  (cl-weave:it-each ((:below-limit 1024)
                     (:at-limit 1025)
                     (:above-limit 1026)
                     (:long-above-limit 4096))
      "classifies dotted keys at and beyond the depth boundary: ~S, ~D segments"
      (label segment-count)
    (let ((*toml-max-nesting-depth* 1024)
          (source (%reader-property-dotted-key-source segment-count)))
      (expect
       (sb-ext:with-timeout 5
         (eq (handler-case
                 (progn (parse source) :accepted)
               (toml-parse-error () :rejected))
             (if (<= segment-count 1025) :accepted :rejected))))))
  (cl-weave:it-fuzz
   "returns a value or signals a TOML kit error for random and valid-mutated byte files"
      ((octets (%reader-property-octets-generator)))
    (:trials 16 :timeout-per-trial 8)
    (%reader-property-run-with-fail-fast-timeout
     "reading a generated byte file"
     (lambda ()
       (%reader-property-with-byte-file
        octets
        (lambda (pathname) (parse-file pathname))))))
  (cl-weave:it-fuzz
   "edits valid UTF-8 TOML byte inputs after mutation"
      ((octets (%reader-property-valid-mutated-octets-generator)))
    (:trials 16 :timeout-per-trial 8)
    (let ((edited (edit-toml octets (list "value") 0)))
      (expect (typep edited
                     (quote (vector (unsigned-byte 8))))))))
