(in-package #:cl-toml-kit/test)

(defun %reader-test-nested-arrays (depth)
  (with-output-to-string (stream)
    (loop repeat depth
          do (write-char #\[ stream))
    (write-char #\0 stream)
    (loop repeat depth
          do (write-char #\] stream))))

(defun %reader-test-nested-inline-tables (depth)
  (with-output-to-string (stream)
    (loop repeat depth
          do (write-string "{a = " stream))
    (write-char #\0 stream)
    (loop repeat depth
          do (write-char #\} stream))))

(defun %reader-test-nesting-error (text &optional source-name)
  (handler-case (progn
                  (parse text :source-name source-name)
                  nil)
    (toml-parse-error (condition)
      condition)))

(defun %reader-test-nesting-result (thunk &optional condition-p)
  (handler-case (progn
                  (funcall thunk)
                  :returned)
    (cl-toml-kit::toml-format-preservation-error (condition)
      (if condition-p condition :toml-format-preservation-error))
    (toml-parse-error (condition)
      (if condition-p condition :toml-parse-error))
    (cl-toml-kit::toml-kit-error (condition)
      (if condition-p condition :toml-kit-error))
    (storage-condition (condition)
      (if condition-p condition (type-of condition)))
    (serious-condition (condition)
      (if condition-p condition (type-of condition)))))

(defun %reader-test-condition-report (condition)
  (typecase condition
    (toml-parse-error
     (list (type-of condition)
           (toml-parse-error-position condition)
           (toml-parse-error-expected condition)))
    (cl-toml-kit::toml-format-preservation-error
     (list (type-of condition)
           (cl-toml-kit:toml-format-preservation-error-message condition)))
    (t (list (type-of condition) nil))))

(defun %reader-test-nested-source (kind depth)
  (labels ((write-path (stream)
             (loop for index below depth
                   do (when (plusp index)
                        (write-char #\. stream))
                      (write-char #\a stream))))
    (with-output-to-string (stream)
      (ecase kind
        (:dotted-key
         (write-path stream)
         (write-string " = 0" stream)
         (terpri stream))
        (:table-header
         (write-char #\[ stream)
         (write-path stream)
         (write-char #\] stream)
         (terpri stream)
         (write-string "value = 0" stream)
         (terpri stream))
        (:array-of-tables
         (write-string "[[" stream)
         (write-path stream)
         (write-string "]]" stream)
         (terpri stream)
         (write-string "value = 0" stream)
         (terpri stream))
        (:inline-dotted-key
         (write-string "value = {" stream)
         (write-path stream)
         (write-string " = 0}" stream)
         (terpri stream))))))

(defun %reader-test-file-nesting-result (text &optional condition-p)
  (let ((bytes (map '(vector (unsigned-byte 8)) #'char-code text)))
    (uiop:with-temporary-file (:stream stream :pathname pathname
                               :directory (uiop:temporary-directory)
                               :prefix "cl-toml-kit-reader-nesting-"
                               :element-type '(unsigned-byte 8))
      (write-sequence bytes stream)
      :close-stream
      (if condition-p
          (handler-case (parse-file pathname)
            (toml-parse-error (condition)
              condition))
          (%reader-test-nesting-result
           (lambda () (parse-file pathname)))))))

(defun %reader-test-nested-edit-path (kind depth)
  (let ((path
          (append (if (eq kind :inline-dotted-key)
                      '("value")
                      nil)
                  (loop repeat depth collect "a"))))
    (case kind
      (:table-header (append path '("value")))
      (:array-of-tables (append path '(0 "value")))
      (otherwise path))))

(describe "reader nesting limits"
          (it "accepts arrays at depth 1024 and rejects depth 1025"
              (let* ((*toml-max-nesting-depth* 1024)
                     (valid-source
                       (format nil "value = ~A" (%reader-test-nested-arrays 1024)))
                     (valid (parse valid-source))
                     (file-valid (%reader-test-file-nesting-result valid-source))
                     (source
                       (format nil "value = ~A" (%reader-test-nested-arrays 1025)))
                     (condition (%reader-test-nesting-error source))
                     (file-condition (%reader-test-file-nesting-result source t))
                     (expected-position (+ (length "value = ") 1024))
                     (expected-message
                       (nth-value 1 (cl-toml-kit::%toml-limit :nesting-depth)))
                     (expected-error-report
                       (list 'toml-parse-error expected-position expected-message)))
                (expect (equal (list t :returned)
                               (list (hash-table-p valid) file-valid)))
                (expect (equal expected-error-report
                               (%reader-test-condition-report condition)))
                (expect (equal expected-error-report
                               (%reader-test-condition-report file-condition)))))
          (it "accepts inline tables at depth 1024 and rejects depth 1025"
              (let* ((*toml-max-nesting-depth* 1024)
                     (valid-source
                       (format nil "value = ~A" (%reader-test-nested-inline-tables 1024)))
                     (valid (parse valid-source))
                     (file-valid (%reader-test-file-nesting-result valid-source))
                     (source
                       (format nil "value = ~A" (%reader-test-nested-inline-tables 1025)))
                     (condition (%reader-test-nesting-error source))
                     (file-condition (%reader-test-file-nesting-result source t))
                     (expected-position (+ (length "value = ") (* 5 1024)))
                     (expected-message
                       (nth-value 1 (cl-toml-kit::%toml-limit :nesting-depth)))
                     (expected-error-report
                       (list 'toml-parse-error expected-position expected-message)))
                (expect (equal (list t :returned)
                               (list (hash-table-p valid) file-valid)))
                (expect (equal expected-error-report
                               (%reader-test-condition-report condition)))
                (expect (equal expected-error-report
                               (%reader-test-condition-report file-condition)))))
          (it-each ((:dotted-key 1025)
                    (:table-header 1024)
                    (:array-of-tables 1023)
                    (:inline-dotted-key 1024))
              "accepts ~S with ~D key components at the limit through parse, parse-file, and edit-toml"
              (kind depth)
            (let* ((*toml-max-nesting-depth* 1024)
                   (*toml-max-path-components* 4096)
                   (source (%reader-test-nested-source kind depth))
                   (bytes (%edit-test-bytes source))
                   (path (%reader-test-nested-edit-path kind depth))
                   (parse-result
                    (%reader-test-nesting-result
                     (lambda () (parse source))))
                   (file-result (%reader-test-file-nesting-result source))
                   (edit-result
                    (%reader-test-nesting-result
                     (lambda () (edit-toml bytes path 1)))))
              (expect (eq :returned parse-result))
              (expect (eq :returned file-result))
              (expect (eq :returned edit-result))))
          (it "counts current table depth when accepting dotted keys at the limit through parse, parse-file, and edit-toml"
              (let* ((*toml-max-nesting-depth* 4)
                     (source (format nil "[root]~%a.b.c.value = 0~%"))
                     (bytes (%edit-test-bytes source))
                     (path (list "root" "a" "b" "c" "value"))
                     (parse-result
                      (%reader-test-nesting-result
                       (lambda () (parse source))))
                     (file-result (%reader-test-file-nesting-result source))
                     (edit-result
                      (%reader-test-nesting-result
                       (lambda () (edit-toml bytes path 1)))))
                (expect (eq :returned parse-result))
                (expect (eq :returned file-result))
                (expect (eq :returned edit-result))))
          (it "accepts repeated dotted keys in an inline table below the nesting limit"
    (let* ((*toml-max-nesting-depth* 6)
           (result (parse "x = {a.b.c.p = 1, a.b.c.q = 1}"))
           (table (gethash "x" result))
           (nested (gethash "c" (gethash "b" (gethash "a" table)))))
      (expect (hash-table-p table))
      (expect (= 1 (gethash "p" nested)))
      (expect (= 1 (gethash "q" nested)))))
          (it "finalizes nested arrays as simple vectors"
    (let* ((*toml-max-nesting-depth* 2)
           (result (parse "value = [[1]]"))
           (table (gethash "value" result))
           (nested (aref table 0)))
      (expect (simple-vector-p table))
      (expect (simple-vector-p nested))
      (expect (equalp #(#(1)) table))))
          (it "keeps direct reader depth guards fail closed"
            (let ((expected-message "TOML nesting depth limit exceeded")
                  (helper-called nil))
              (let* ((*toml-max-nesting-depth* 1)
                     (root (make-hash-table :test (function equal)))
                     (state
                       (cl-toml-kit::%make-reader-state
                        :source "[a.b]" :length 5 :root root))
                     (condition
                       (handler-case
                           (progn
                             (cl-toml-kit::%define-header-table
                              state 0 (list "a" "b") nil
                              (lambda (value)
                                (declare (ignore value)))
                              (lambda (position expected path)
                                (declare (ignore position expected path))))
                             nil)
                         (toml-parse-error (condition) condition))))
                (expect
                 (equal (list (find-symbol "TOML-PARSE-ERROR" "CL-TOML-KIT")
                              0
                              expected-message)
                        (%reader-test-condition-report condition))))
              (let* ((*toml-max-nesting-depth* 0)
                     (root (make-hash-table :test (function equal)))
                     (state
                       (cl-toml-kit::%make-reader-state
                        :source "a.b = 1" :length 7 :root root))
                     (condition
                       (handler-case
                           (progn
                             (cl-toml-kit::%read-document-assignment-value
                              state (list "a" "b") 6
                              (lambda (value position)
                                (declare (ignore value position)))
                              (lambda (position expected path)
                                (declare (ignore position expected path))))
                             nil)
                         (toml-parse-error (condition) condition))))
                (expect
                 (equal (list (find-symbol "TOML-PARSE-ERROR" "CL-TOML-KIT")
                              6
                              expected-message)
                        (%reader-test-condition-report condition))))
              (let* ((*toml-max-nesting-depth* 1)
                     (state
                       (cl-toml-kit::%make-reader-state
                        :source "{}" :length 2 :nesting-depth 1))
                     (condition
                       (handler-case
                           (cl-toml-kit::%call-with-reader-nesting-depth
                            state 0 nil 2
                            (lambda () (setf helper-called t)))
                         (toml-parse-error (condition) condition))))
                (expect
                 (equal (list (find-symbol "TOML-PARSE-ERROR" "CL-TOML-KIT")
                              0
                              expected-message)
                        (%reader-test-condition-report condition)))
                (expect (not helper-called))
                (expect (= 1 (cl-toml-kit::toml-reader-state-nesting-depth
                              state))))))
          (it "finalizes nested arrays of tables"
            (let* ((document
                     (parse
                      (format nil
                              "[[fruit]]~%name = \"apple\"~%[[fruit.variety]]~%name = \"red\"~%[[fruit.variety]]~%name = \"green\"~%")))
                   (fruits (gethash "fruit" document))
                   (fruit (aref fruits 0))
                   (varieties (gethash "variety" fruit)))
              (expect (simple-vector-p fruits))
              (expect (simple-vector-p varieties))
              (expect (= 2 (length varieties)))
              (expect (equal "apple" (gethash "name" fruit)))
              (expect (equal "red" (gethash "name" (aref varieties 0))))
              (expect (equal "green" (gethash "name" (aref varieties 1))))))
          (it "accepts inline dotted keys at depth one below the limit"
    (let* ((*toml-max-nesting-depth* 6)
           (result (parse "x = {a.b.c.d.p = 1, a.b.c.d.q = 1}"))
           (table (gethash "x" result))
           (nested (gethash "d" (gethash "c" (gethash "b" (gethash "a" table))))))
      (expect (hash-table-p table))
      (expect (= 1 (gethash "p" nested)))
      (expect (= 1 (gethash "q" nested)))))
          (it "counts current table depth when rejecting dotted keys above the limit through parse, parse-file, and edit-toml"
              (let* ((*toml-max-nesting-depth* 4)
                     (source (format nil "[root]~%a.b.c.d.value = 0~%"))
                     (bytes (%edit-test-bytes source))
                     (path (list "root" "a" "b" "c" "d" "value"))
                     (parse-result
                      (%reader-test-nesting-result
                       (lambda () (parse source))))
                     (file-result (%reader-test-file-nesting-result source))
                     (edit-result
                      (%reader-test-nesting-result
                       (lambda () (edit-toml bytes path 1)))))
                (expect (eq :toml-parse-error parse-result))
                (expect (eq :toml-parse-error file-result))
                (expect (eq :toml-format-preservation-error edit-result))))
          (it-each ((:dotted-key 1026)
                    (:table-header 1025)
                    (:array-of-tables 1024)
                    (:inline-dotted-key 1025))
              "rejects ~S with ~D key components above the limit through parse, parse-file, and edit-toml"
              (kind depth)
            (let* ((*toml-max-nesting-depth* 1024)
                   (*toml-max-path-components* 4096)
                   (source (%reader-test-nested-source kind depth))
                   (bytes (%edit-test-bytes source))
                   (path (%reader-test-nested-edit-path kind depth))
                   (parse-result
                    (%reader-test-nesting-result
                     (lambda () (parse source))))
                   (file-result (%reader-test-file-nesting-result source))
                   (edit-result
                    (%reader-test-nesting-result
                     (lambda () (edit-toml bytes path 1)))))
              (expect (eq :toml-parse-error parse-result))
              (expect (eq :toml-parse-error file-result))
              (expect
               (eq :toml-format-preservation-error edit-result))))
          (it "rejects 100000-component dotted keys at the first excess component through parse, parse-file, and edit-toml"
              (let* ((*toml-max-nesting-depth* 1024)
                     (source (%reader-test-nested-source :dotted-key 100000))
                     (bytes (%edit-test-bytes source))
                     (parse-condition (%reader-test-nesting-error source))
                     (file-condition
                       (%reader-test-file-nesting-result source t))
                     (expected-position (* 2 *toml-max-nesting-depth*))
                     (expected-message
                       (nth-value 1 (cl-toml-kit::%toml-limit :nesting-depth)))
                     (edit-condition
                       (%reader-test-nesting-result
                        (lambda () (edit-toml bytes '("value") 0))
                        t)))
                (expect
                 (equal (list 'toml-parse-error expected-position expected-message)
                        (%reader-test-condition-report parse-condition)))
                (expect
                 (equal (list 'toml-parse-error expected-position expected-message)
                        (%reader-test-condition-report file-condition)))
                (expect
                 (equal (list 'toml-format-preservation-error expected-message)
                        (%reader-test-condition-report edit-condition)))))
          (it "rejects 100000-component table headers at the first excess component through parse, parse-file, and edit-toml"
              (let* ((*toml-max-nesting-depth* 1024)
                     (source (%reader-test-nested-source :table-header 100000))
                     (bytes (%edit-test-bytes source))
                     (parse-condition (%reader-test-nesting-error source))
                     (file-condition
                       (%reader-test-file-nesting-result source t))
                     (expected-position (+ 1 (* 2 *toml-max-nesting-depth*)))
                     (expected-message
                       (nth-value 1 (cl-toml-kit::%toml-limit :nesting-depth)))
                     (edit-condition
                       (%reader-test-nesting-result
                        (lambda () (edit-toml bytes '("value") 0))
                        t)))
                (expect
                 (equal (list 'toml-parse-error expected-position expected-message)
                        (%reader-test-condition-report parse-condition)))
                (expect
                 (equal (list 'toml-parse-error expected-position expected-message)
                        (%reader-test-condition-report file-condition)))
                (expect
                 (equal (list 'toml-format-preservation-error expected-message)
                        (%reader-test-condition-report edit-condition)))))
          (it "rejects 100000-component array table headers at the first excess component through parse, parse-file, and edit-toml"
              (let* ((*toml-max-nesting-depth* 1024)
                     (source (%reader-test-nested-source :array-of-tables 100000))
                     (bytes (%edit-test-bytes source))
                     (parse-condition (%reader-test-nesting-error source))
                     (file-condition
                       (%reader-test-file-nesting-result source t))
                     (expected-position (+ 2 (* 2 (1- *toml-max-nesting-depth*))))
                     (expected-message
                       (nth-value 1 (cl-toml-kit::%toml-limit :nesting-depth)))
                     (edit-condition
                       (%reader-test-nesting-result
                        (lambda () (edit-toml bytes '("value") 0))
                        t)))
                (expect
                 (equal (list 'toml-parse-error expected-position expected-message)
                        (%reader-test-condition-report parse-condition)))
                (expect
                 (equal (list 'toml-parse-error expected-position expected-message)
                        (%reader-test-condition-report file-condition)))
                (expect
                 (equal (list 'toml-format-preservation-error expected-message)
                        (%reader-test-condition-report edit-condition)))))
          (it "rejects 100000-component inline dotted keys at the first excess component through parse, parse-file, and edit-toml"
              (let* ((*toml-max-nesting-depth* 1024)
                     (source (%reader-test-nested-source :inline-dotted-key 100000))
                     (bytes (%edit-test-bytes source))
                     (parse-condition (%reader-test-nesting-error source))
                     (file-condition
                       (%reader-test-file-nesting-result source t))
                     (expected-position
                       (+ (length "value = {")
                          (* 2 (1- *toml-max-nesting-depth*))))
                     (expected-message
                       (nth-value 1 (cl-toml-kit::%toml-limit :nesting-depth)))
                     (edit-condition
                       (%reader-test-nesting-result
                        (lambda () (edit-toml bytes '("value") 0))
                        t)))
                (expect
                 (equal (list 'toml-parse-error expected-position expected-message)
                        (%reader-test-condition-report parse-condition)))
                (expect
                 (equal (list 'toml-parse-error expected-position expected-message)
                        (%reader-test-condition-report file-condition)))
                (expect
                 (equal (list 'toml-format-preservation-error expected-message)
                        (%reader-test-condition-report edit-condition)))))
          (it "rejects 100000-level arrays and inline tables through parse"
              (let* ((*toml-max-nesting-depth* 1024)
                     (array-result
                      (%reader-test-nesting-result
                       (lambda ()
                         (parse
                          (format nil "value = ~A"
                                  (%reader-test-nested-arrays 100000))))))
                     (inline-result
                      (%reader-test-nesting-result
                       (lambda ()
                         (parse
                          (format nil "value = ~A"
                                  (%reader-test-nested-inline-tables 100000)))))))
                (expect (eq :toml-parse-error array-result))
                (expect (eq :toml-parse-error inline-result))))
          (it "rejects 100000-level arrays and inline tables through edit-toml"
              (let* ((*toml-max-nesting-depth* 1024)
                     (array-source
                      (%edit-test-bytes
                       (format nil "value = ~A"
                               (%reader-test-nested-arrays 100000))))
                     (inline-source
                      (%edit-test-bytes
                       (format nil "value = ~A"
                               (%reader-test-nested-inline-tables 100000))))
                     (array-result
                      (%reader-test-nesting-result
                       (lambda () (edit-toml array-source '("value") 0))))
                     (inline-result
                      (%reader-test-nesting-result
                       (lambda () (edit-toml inline-source '("value") 0)))))
                (expect
                 (eq :toml-format-preservation-error array-result))
                (expect
                 (eq :toml-format-preservation-error inline-result))))
          (it "normalizes source names on nesting-limit errors"
              (let* ((*toml-max-nesting-depth* 1)
                     (pathname #p"reader-nesting-security.toml")
                     (expected-message
                       (nth-value 1 (cl-toml-kit::%toml-limit :nesting-depth)))
                     (text (format nil "value = ~A" (%reader-test-nested-arrays 2)))
                     (pathname-condition
                       (%reader-test-nesting-error text pathname))
                     (controls
                       (coerce (list (code-char 0)
                                     (code-char #x1B)
                                     (code-char #x80)
                                     (code-char #x9F)
                                     (code-char #x7F))
                               'string))
                     (source-name
                       (concatenate 'string "nesting-" controls
                                    (make-string 300 :initial-element #\x)))
                     (escaped-condition
                       (%reader-test-nesting-error text source-name))
                     (escaped-source-name
                       (and (typep escaped-condition 'toml-parse-error)
                            (toml-parse-error-source-name escaped-condition)))
                     (escape-sequence "\\u0000\\u001B\\u0080\\u009F\\u007F")
                     (escaped-expected
                       (and (typep escaped-condition 'toml-parse-error)
                            (toml-parse-error-expected escaped-condition)))
                     (escape-sequence-present
                       (and (stringp escaped-source-name)
                            (search escape-sequence escaped-source-name)))
                     (source-name-within-limit
                       (and (stringp escaped-source-name)
                            (<= (length escaped-source-name)
                                cl-toml-kit::+toml-diagnostic-limit+)))
                     (source-name-has-no-c0-controls
                       (and (stringp escaped-source-name)
                            (notany (lambda (character)
                                      (< (char-code character) 32))
                                    escaped-source-name)))
                     (source-name-has-no-c1-controls
                       (and (stringp escaped-source-name)
                            (notany (lambda (character)
                                      (<= #x7F (char-code character) #x9F))
                                    escaped-source-name))))
                (expect
                 (equal (list 'toml-parse-error
                              (namestring pathname)
                              expected-message)
                        (list (type-of pathname-condition)
                              (and (typep pathname-condition 'toml-parse-error)
                                   (toml-parse-error-source-name pathname-condition))
                              (and (typep pathname-condition 'toml-parse-error)
                                   (toml-parse-error-expected pathname-condition)))))
                (expect (typep escaped-condition 'toml-parse-error))
                (expect (stringp escaped-source-name))
                (expect (equal expected-message escaped-expected))
                (expect escape-sequence-present)
                (expect source-name-within-limit)
                (expect source-name-has-no-c0-controls)
                (expect source-name-has-no-c1-controls)))
          (it "rejects an over-limit quoted dotted key"
            (let* ((*toml-max-nesting-depth* 1)
                   (expected-error-report
                     (list (find-symbol "TOML-PARSE-ERROR" "CL-TOML-KIT")
                           2
                           "TOML nesting depth limit exceeded"))
                   (condition (%reader-test-nesting-error "a.\"b\".c = 1"))
                   (escaped-condition (%reader-test-nesting-error "a.\"b\\u0063\".c = 1")))
              (expect (equal expected-error-report
                             (%reader-test-condition-report condition)))
              (expect (equal expected-error-report
                             (%reader-test-condition-report escaped-condition)))))
          (it "rejects triple-quoted keys before dotted-key lookahead"
            (let* ((*toml-max-nesting-depth* 1)
                   (expected-message
                     (cl-toml-kit::%toml-reader-error-message :single-line-key))
                   (expected-error-report
                     (list (quote toml-parse-error) 2 expected-message))
                   (simple-condition
                     (%reader-test-nesting-error "a.\"\"\"b\"\"\".c = 1"))
                   (escaped-condition
                     (%reader-test-nesting-error "a.\"\"\"b\\u0063\"\"\".c = 1")))
              (expect (equal expected-error-report
                             (%reader-test-condition-report simple-condition)))
              (expect (equal expected-error-report
                             (%reader-test-condition-report escaped-condition)))))


)
