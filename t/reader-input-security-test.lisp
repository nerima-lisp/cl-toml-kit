(in-package #:cl-toml-kit/test)

(defun %reader-input-error (thunk)
  (handler-case
      (progn (funcall thunk) nil)
    (toml-parse-error (condition) condition)))

(defun %reader-input-surrogate-source (context)
  (let ((surrogate (string (code-char #xd800))))
    (ecase context
      (:basic-string
       (concatenate 'string "value = \"" surrogate "\""))
      (:literal-string
       (concatenate 'string "value = '" surrogate "'"))
      (:multiline-basic-string
       (concatenate 'string "value = \"\"\"" surrogate "\"\"\""))
      (:multiline-literal-string
       (concatenate 'string "value = '''" surrogate "'''"))
      (:quoted-key
       (concatenate 'string "\"" surrogate "\" = 1"))
      (:comment
       (concatenate 'string "# " surrogate)))))

(progn
  (defun %reader-input-with-byte-file (bytes thunk)
    (uiop:with-temporary-file (:stream stream :pathname pathname
                               :directory (uiop:temporary-directory)
                               :prefix "cl-toml-kit-reader-"
                               :element-type '(unsigned-byte 8))
      (write-sequence bytes stream)
      :close-stream
      (funcall thunk pathname)))
  #+sbcl
  (defclass %reader-counting-byte-stream
      (sb-gray:fundamental-binary-input-stream)
    ((available-bytes :initarg :available-bytes
                      :reader %reader-counting-byte-stream-available-bytes)
     (position :initform 0
               :accessor %reader-counting-byte-stream-position)
     (read-sizes :initform nil
                 :accessor %reader-counting-byte-stream-read-sizes)))
  #+sbcl
  (defmethod sb-gray:stream-read-sequence
      ((stream %reader-counting-byte-stream) sequence
       &optional (start 0) (end (length sequence)))
    (let* ((position (%reader-counting-byte-stream-position stream))
           (count (min (- end start)
                       (- (%reader-counting-byte-stream-available-bytes stream)
                          position)))
           (next (+ start count)))
      (loop for index from start below next
            do (setf (elt sequence index) 0))
      (setf (%reader-counting-byte-stream-position stream) (+ position count))
      (push count (%reader-counting-byte-stream-read-sizes stream))
      next)))

(describe "reader input security"
  (it-each ((:basic-string)
            (:literal-string)
            (:multiline-basic-string)
            (:multiline-literal-string)
            (:quoted-key)
            (:comment))
      "rejects a raw surrogate in ~A input"
      (context)
    (let ((condition
            (%reader-input-error
             (lambda ()
               (parse (%reader-input-surrogate-source context))))))
      (expect (typep condition 'toml-parse-error))
      (expect (string= "Unicode scalar value"
                       (toml-parse-error-expected condition)))))
  (it "checks the string character limit before parsing invalid TOML"
    (let* ((text "value = [")
           (*toml-max-input-characters* (1- (length text)))
           (condition
             (%reader-input-error (lambda () (parse text)))))
      (expect (typep condition 'toml-parse-error))
      (expect (string= "TOML input character limit exceeded"
                       (toml-parse-error-expected condition)))))
  (it "stops a character stream after reading limit plus one"
    (with-input-from-string (stream "value = [ trailing text")
      (let* ((*toml-max-input-characters* 4)
             (condition
               (%reader-input-error (lambda () (parse stream)))))
        (expect (string= "TOML input character limit exceeded"
                         (toml-parse-error-expected condition)))
        (expect (= 5 (file-position stream))))))
  (it "reports source location for file byte-limit errors"
      (let* ((bytes (make-array 4 :element-type '(unsigned-byte 8)
                                :initial-element #xff))
             (*toml-max-input-bytes* 3)
             (source-name nil)
             (condition
              (%reader-input-with-byte-file
               bytes
               (lambda (pathname)
                 (setf source-name (namestring pathname))
                 (%reader-input-error
                  (lambda () (parse-file pathname))))))
             (report (princ-to-string condition)))
        (expect (typep condition 'toml-parse-error))
        (expect (= 0 (toml-parse-error-position condition)))
        (expect (null (toml-parse-error-line condition)))
        (expect (null (toml-parse-error-column condition)))
        (expect (search "at position 0" report))
        (expect (not (search "at line" report)))
        (expect (not (search "column" report)))
        (expect (not (search "null" report)))
        (expect (string= source-name
                         (toml-parse-error-source-name condition)))))
  (it "checks the file byte limit before decoding invalid UTF-8"
    (let* ((bytes (make-array 4 :element-type '(unsigned-byte 8)
                              :initial-element #xff))
           (*toml-max-input-bytes* 3)
           (condition
             (%reader-input-with-byte-file
              bytes
              (lambda (pathname)
                (%reader-input-error
                 (lambda () (parse-file pathname)))))))
      (expect (string= "TOML input byte limit exceeded"
                       (toml-parse-error-expected condition)))))
  (it "reads incrementally when the reported file length is zero"
    (let* ((*toml-max-input-bytes* 4)
           (reported-length
             (with-open-file (stream #P"/dev/zero"
                             :direction :input
                             :element-type (quote (unsigned-byte 8)))
               (file-length stream)))
           (condition
             (%reader-input-error
              (lambda () (parse-file #P"/dev/zero")))))
      (expect (zerop reported-length))
      (expect condition)
      (expect (string= "TOML input byte limit exceeded"
                       (toml-parse-error-expected condition)))
      (expect (zerop (toml-parse-error-position condition)))
      (expect (string= "" (toml-parse-error-text condition)))))
  (it "parse-file reads unknown-length byte streams incrementally up to the byte limit"
    (when (find-package :sb-gray)
      (let* ((*toml-max-input-bytes* 70000)
             (stream (make-instance
                                  '%reader-counting-byte-stream
                                  :available-bytes 200000)))
        (let ((condition
                (%reader-input-error
                 (lambda ()
                   (cl-toml-kit::%parse-file-stream
                    stream nil "unknown-length" nil)))))
          (expect (string= "TOML input byte limit exceeded"
                     (toml-parse-error-expected condition)))
          (expect (= (1+ *toml-max-input-bytes*)
                     (%reader-counting-byte-stream-position stream)))
          (expect (equal '(65536 4465)
                         (reverse
                          (%reader-counting-byte-stream-read-sizes stream))))))))
  (it "checks decoded file characters before parsing invalid TOML"
      (let* ((text "value = [")
             (bytes (map '(vector (unsigned-byte 8)) #'char-code text))
             (*toml-max-input-bytes* (length bytes))
             (*toml-max-input-characters* (1- (length text)))
             (condition
              (%reader-input-with-byte-file
               bytes
               (lambda (pathname)
                 (%reader-input-error
                  (lambda () (parse-file pathname)))))))
        (expect (typep condition 'toml-parse-error))
        (expect (string= "TOML input character limit exceeded"
                         (toml-parse-error-expected condition)))
        (expect (= (1- (length text))
                   (toml-parse-error-position condition)))
        (expect (null (toml-parse-error-line condition)))
        (expect (null (toml-parse-error-column condition)))
        (expect (string= text (toml-parse-error-text condition)))))
  (it "reports diagnostic positions at CRLF boundaries"
    (dolist (case
             (list (list (format nil "a~C~C" #\Return #\Newline) 2 2 1)
                   (list (format nil "a~CX~C" #\Return #\Newline) 3 2 2)
                   (list (format nil "a~C~CX" #\Return #\Newline) 3 2 1)))
      (destructuring-bind (source position expected-line expected-column) case
        (let ((condition
                (%reader-input-error
                 (lambda ()
                   (cl-toml-kit::%error-at-message
                    (cl-toml-kit::%make-reader-state
                     :source source :length (length source))
                    position "reader position probe")))))
          (expect (typep condition (find-class (quote cl-toml-kit::toml-parse-error))))
          (expect (= position (toml-parse-error-position condition)))
          (expect (= expected-line (toml-parse-error-line condition)))
          (expect (= expected-column (toml-parse-error-column condition)))
          (expect (string= "reader position probe"
                           (toml-parse-error-expected condition)))))))
  (it "preserves TAB in basic and literal strings"
    (let* ((tab #\Tab)
           (quote-char (code-char 39))
           (source
             (format nil
                     "basic = \"left~Cright\"~%literal = ~Cleft~Cright~C"
                     tab quote-char tab quote-char))
           (document (parse source)))
      (expect (string= (format nil "left~Cright" tab)
                       (gethash "basic" document)))
      (expect (string= (format nil "left~Cright" tab)
                       (gethash "literal" document)))))
  (it "accepts TAB and rejects other controls in reader string helpers"
    (dolist (delimiter (list #\" (code-char 39)))
      (let* ((tab-source (format nil "~C~C~C" delimiter #\Tab delimiter))
             (tab-state
               (cl-toml-kit::%make-reader-state
                :source tab-source :length (length tab-source)))
             (tab-result
               (cl-toml-kit::%read-string-character
                tab-state 1 delimiter nil
                (lambda (next) (list :accepted next))
                (lambda (position expected path)
                  (list :rejected position expected path)))))
        (expect (= 2
                   (cl-toml-kit::%simple-string-end tab-state 0 delimiter)))
        (expect (equal (list :accepted 2) tab-result))
        (expect (string= (string #\Tab)
                         (coerce
                          (cl-toml-kit::toml-reader-state-buffer tab-state)
                          (quote string)))))
      (let* ((control (code-char 1))
             (source (format nil "~C~C~C" delimiter control delimiter))
             (state
               (cl-toml-kit::%make-reader-state
                :source source :length (length source)))
             (result
               (cl-toml-kit::%read-string-character
                state 1 delimiter nil
                (lambda (next) (list :accepted next))
                (lambda (position expected path)
                  (list :rejected position expected path)))))
        (expect (null
                 (cl-toml-kit::%simple-string-end state 0 delimiter)))
        (expect (equal
                 (list :rejected 1 :printable-string-character nil)
                 result)))))
  (it "reports public control character positions"
    (let* ((control (code-char 1))
           (source (format nil "value = \"left~Cright\"" control))
           (position (position control source))
           (condition
             (%reader-input-error
              (lambda () (parse source)))))
      (expect (typep condition
                     (find-class (quote cl-toml-kit::toml-parse-error))))
      (expect (string= "printable character"
                       (toml-parse-error-expected condition)))
      (expect (= position (toml-parse-error-position condition)))
      (expect (= 1 (toml-parse-error-line condition)))
      (expect (= (1+ position) (toml-parse-error-column condition)))))
  (it "reports invalid UTF-8 positions after CR boundaries"
    (dolist (case
             (list (list (vector 97 13 255 10) 2 2 1)
                   (list (vector 97 13 88 255) 3 2 2)
                   (list (vector 97 13 10 255) 3 2 1)))
      (destructuring-bind (octets position expected-line expected-column) case
        (let* ((bytes
                 (make-array (length octets)
                            :element-type (quote (unsigned-byte 8))
                            :initial-contents octets))
               (condition
                 (%reader-input-with-byte-file
                  bytes
                  (lambda (pathname)
                    (%reader-input-error
                     (lambda () (parse-file pathname)))))))
          (expect (typep condition
                         (find-class (quote cl-toml-kit::toml-parse-error))))
          (expect (string= "UTF-8" (toml-parse-error-expected condition)))
          (expect (= position (toml-parse-error-position condition)))
          (expect (= expected-line (toml-parse-error-line condition)))
          (expect (= expected-column (toml-parse-error-column condition))))))))
