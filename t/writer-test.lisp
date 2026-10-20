(in-package #:cl-toml-kit/test)

(defun %writer-table (&rest pairs)
  (let ((table (make-hash-table :test 'equal)))
    (loop for (key value) on pairs by #'cddr
          do (setf (gethash key table) value))
    table))

(defun %writer-nan ()
  (gethash "x" (cl-toml-kit:parse "x = nan")))

(defun %writer-float-value (text)
  (cond ((string= text "inf") sb-ext:double-float-positive-infinity)
        ((string= text "-inf") sb-ext:double-float-negative-infinity)
        ((string= text "nan") (%writer-nan))
        (t (let ((*read-eval* nil)
                 (*read-default-float-format* 'double-float))
             (read-from-string text)))))

(defun %writer-float-text (encoded)
  (subseq encoded (length "value = ") (1- (length encoded))))

(defun %writer-valid-line-p (line)
  (or (and (> (length line) 2)
           (char= #\[ (char line 0))
           (if (char= #\[ (char line 1))
               (and (char= #\] (char line (- (length line) 1)))
                    (char= #\] (char line (- (length line) 2))))
               (char= #\] (char line (- (length line) 1)))))
      (let ((separator (search " = " line)))
        (and separator (plusp separator)
             (< (+ separator 3) (length line))))))

(defun %writer-valid-toml-lines-p (text)
  (with-input-from-string (stream text)
    (loop for line = (read-line stream nil)
          while line
          always (%writer-valid-line-p line))))

(defun %writer-generated-values (self)
  (toml-test-value-generator
   self
   :additional-scalars
   (list sb-ext:double-float-positive-infinity
         sb-ext:double-float-negative-infinity
         (%writer-nan))))

(defun %writer-value-line-count (table)
  "Count the value lines that encoding TABLE must emit, excluding headers."
  (loop for key being the hash-keys of table
        using (hash-value value)
        sum (cond ((toml-table-p value)
                   (%writer-value-line-count value))
                  ((and (vectorp value)
                        (plusp (length value))
                        (loop for item across value always (hash-table-p item)))
                   (loop for item across value
                         sum (%writer-value-line-count item)))
                  (t 1))))

(defun %writer-line-count (text)
  "Count newline-terminated lines in encoded TEXT."
  (count #\Newline text))

(describe "TOML writer emitter macro"
  (it "writes values with an emitter generated for one kind"
    (let* ((package (find-package "CL-TOML-KIT/TEST"))
           (name (intern (symbol-name (gensym "WRITER-EMITTER-")) package))
           (cl-toml-kit::*toml-writer-emitter-specifications*
             '((:string (write-string value stream)))))
      (unwind-protect
           (progn
             (eval (list 'cl-toml-kit::define-toml-emitter
                         name '(value stream path)))
             (let ((stream (make-string-output-stream)))
               (funcall (symbol-function name) "generated value" stream nil)
               (expect (string= "generated value"
                                (get-output-stream-string stream)))))
        (when (fboundp name)
          (fmakunbound name))
        (unintern name package))))
  (it "signals a value model error for an unknown emitter kind"
    (let* ((package (find-package "CL-TOML-KIT/TEST"))
           (name (intern (symbol-name (gensym "WRITER-EMITTER-")) package))
           (cl-toml-kit::*toml-writer-emitter-specifications*
             '((:unknown (write-string value stream)))))
      (unwind-protect
           (let ((expansion
                   (macroexpand-1
                    (list 'cl-toml-kit::define-toml-emitter
                          name '(value stream path)))))
             (expect (signals toml-value-model-error
                       (macroexpand-1 (cadddr expansion)))))
        (unintern name package)))))

(describe "TOML writer scalar data"
  (it-each (("hello" "message = \"hello\"~%")
            ("café 🧪" "message = \"café 🧪\"~%")
            (42 "message = 42~%")
            (1.5d0 "message = 1.5~%")
            (1.0d0 "message = 1.0~%")
            (1.0d20 "message = 1.0e20~%")
            (-0.0d0 "message = -0.0~%")
            (t "message = true~%"))
      "writes ~S as ~S"
      (value expected)
    (expect (string= (format nil expected)
                     (encode (%writer-table "message" value)))))
  (it "writes the false sentinel"
    (expect (string= (format nil "message = false~%")
                     (encode (%writer-table "message" +toml-false+)))))
  (it-property "reads back every generated double-float"
      ((value (gen-member (list -0.0d0 0.0d0 1.5d0 1.0d20
                                  least-positive-double-float
                                  most-positive-double-float
                                  sb-ext:double-float-positive-infinity
                                  sb-ext:double-float-negative-infinity
                                  (%writer-nan)))))
    (let* ((encoded (encode (%writer-table "value" value)))
           (read-back (%writer-float-value (%writer-float-text encoded))))
      (expect
       (sb-int:with-float-traps-masked (:invalid)
         (if (zerop value)
             (eql value read-back)
             (toml-test-value= value read-back))))))
  (it-each ((:offset "offset" "offset = 2026-01-02T03:04:05Z~%")
            (:date-time "date-time" "date-time = 2026-01-02T03:04:05~%")
            (:date "date" "date = 2026-01-02~%")
            (:time "time" "time = 03:04:05~%"))
      "writes ~A values with RFC3339 formatting"
      (kind key expected)
    (let ((value
            (nth (ecase kind
                   (:offset 0)
                   (:date-time 1)
                   (:date 2)
                   (:time 3))
                 (toml-test-date-values))))
      (expect (string= (format nil expected)
                       (encode (%writer-table key value))))))
  (it "writes infinities, NaN, and the smallest subnormal"
    (expect (string= (format nil "a = inf~%b = -inf~%c = nan~%d = 4.9406564584124654e-324~%")
                     (encode (%writer-table
                              "a" sb-ext:double-float-positive-infinity
                              "b" sb-ext:double-float-negative-infinity
                              "c" (%writer-nan)
                              "d" least-positive-double-float)))))
  (it "escapes every basic-string control form including DEL"
    (expect (string= (format nil "value = \"\\b\\t\\n\\f\\r\\\"\\\\\\u0000\\u001F\\u007F\"~%")
                     (encode (%writer-table "value"
                                             (format nil "~C~C~C~C~C~C~C~C~C~C"
                                                     #\Backspace #\Tab #\Newline
                                                     #\Page #\Return #\" #\\
                                                     (code-char 0) (code-char 31)
                                                     (code-char 127)))))))
  (it-each (("plain-key" "plain-key = 1~%")
            ("has space" "\"has space\" = 1~%")
            ("" "\"\" = 1~%")
            ("こんにちは" "\"こんにちは\" = 1~%"))
      "writes key ~S using the correct key syntax"
      (key expected)
    (expect (string= (format nil expected) (encode (%writer-table key 1))))))

(describe "TOML writer containers and paths"
  (it-each (("scalar table" :scalar
             "a = 1~%b = 2~%")
            ("one nested table" :one-nested
             "[child]~%value = 1~%")
            ("two nested tables" :two-nested
             "[child]~%[child.grand]~%leaf = 2~%")
            ("one array table" :one-array
             "[[items]]~%name = \"a\"~%")
            ("two array tables" :two-array
             "[[items]]~%name = \"a\"~%[[items]]~%name = \"b\"~%")
            ("array table with nested table" :array-nested
             "[[items]]~%name = \"a\"~%[items.meta]~%leaf = 1~%")
            ("mixed array and table" :mixed
             "[other]~%value = 2~%[[items]]~%name = \"a\"~%")
            ("empty table" :empty
             "[empty]~%")
            ("array of scalars" :scalar-array
             "values = [1, 2]~%")
            ("empty array" :empty-array
             "values = []~%")
            ("inline table in an array" :inline-array
             "values = [1, { b = 2 }]~%")
            ("empty inline table in an array" :empty-inline-array
             "values = [1, {}]~%")
            ("multi-entry inline table in an array" :multi-inline-array
             "values = [1, { a = 1, b = 2 }]~%")
            ("insertion order" :order
             "first = 1~%second = 2~%third = 3~%"))
      "encodes ~A exactly and deterministically"
      (name kind expected)
    (let* ((value (case kind
                    (:scalar (%writer-table "a" 1 "b" 2))
                    (:one-nested (%writer-table "child" (%writer-table "value" 1)))
                    (:two-nested
                     (%writer-table "child"
                                    (%writer-table "grand" (%writer-table "leaf" 2))))
                    (:one-array (%writer-table "items"
                                               (vector (%writer-table "name" "a"))))
                    (:two-array (%writer-table "items"
                                               (vector (%writer-table "name" "a")
                                                       (%writer-table "name" "b"))))
                    (:array-nested
                     (%writer-table "items"
                                    (vector (%writer-table "name" "a"
                                                           "meta" (%writer-table "leaf" 1)))))
                    (:mixed (%writer-table "items"
                                           (vector (%writer-table "name" "a"))
                                           "other" (%writer-table "value" 2)))
                    (:empty (%writer-table "empty" (make-hash-table :test 'equal)))
                    (:scalar-array (%writer-table "values" (vector 1 2)))
                    (:empty-array (%writer-table "values" #()))
                    (:inline-array (%writer-table "values"
                                                  (vector 1 (%writer-table "b" 2))))
                    (:empty-inline-array
                     (%writer-table "values"
                                    (vector 1 (%writer-table))))
                    (:multi-inline-array
                     (%writer-table "values"
                                    (vector 1 (%writer-table "a" 1 "b" 2))))
                    (:order (%writer-table "first" 1 "second" 2 "third" 3))))
           (first (encode value))
           (second (encode value)))
      (declare (ignore name))
      (expect (and (string= first (format nil expected))
                   (string= first second)))))
  (it "writes directly to the supplied stream and returns the input table"
    (let* ((value (%writer-table "value" 1))
           (stream (make-string-output-stream))
           (result (write-toml value stream))
           (text (get-output-stream-string stream)))
      (expect (eq result value))
      (expect (string= text (format nil "value = 1~%")))))
  (it "writes values before nested tables and preserves paths"
    (let ((child (%writer-table "value" 1))
          (grandchild (%writer-table "leaf" 2)))
      (setf (gethash "grand" child) grandchild)
      (expect (string= (format nil "root = true~%[child]~%value = 1~%[child.grand]~%leaf = 2~%")
                       (encode (%writer-table "child" child "root" t))))))
  (it-property "generated arrays and nested tables are deterministic and line-valid"
      ((value (gen-recursive
               (gen-one-of (gen-integer :min -10 :max 10)
                           (gen-string :max-length 8)
                           (gen-member (list t +toml-false+)))
               #'%writer-generated-values
               :max-depth 3)))
    (let* ((table (%writer-table "value" value))
           (first (encode table))
           (second (encode table)))
      (expect (string= first second))
      (expect (%writer-valid-toml-lines-p first))
      (expect (>= (%writer-line-count first)
                  (%writer-value-line-count table))))))

(describe "TOML writer errors"
  (it-each ((:nil "Unsupported TOML value" ("outer" "inner"))
            (:list "Unsupported TOML value" ("outer" "inner"))
            (:symbol "Unsupported TOML value" ("outer" "inner"))
            (:large-integer "Integer is outside TOML's signed 64-bit range"
                            ("outer" "inner"))
            (:eql-table "Table must use the EQUAL hash-table test" nil)
            (:eql-inline-array "Table must use the EQUAL hash-table test"
                               ("values" 1))
            (:eql-nested-table "Table must use the EQUAL hash-table test"
                               ("section"))
            (:eql-array-table-element "Table must use the EQUAL hash-table test"
                                      ("items"))
            (:non-string-key "Table keys must be strings" ("BAD"))
            (:inline-non-string-key "Table keys must be strings" ("items" 1 "BAD"))
            (:non-table-root "The top-level TOML value must be a hash-table" nil)
            (:adjustable-vector "Unsupported TOML value" ("outer" "inner")))
      "signals a bounded encoding error for ~S"
      (kind expected-message expected-path)
    (let ((condition
            (handler-case
                (encode
                 (case kind
                   (:eql-table (let ((table (make-hash-table :test 'eql)))
                                (setf (gethash "key" table) 1)
                                table))
                   (:eql-inline-array
                    (let ((table (make-hash-table :test 'eql)))
                      (%writer-table "values" (vector 0 table))))
                   (:eql-nested-table
                    (%writer-table "section" (make-hash-table :test 'eql)))
                   (:eql-array-table-element
                    (%writer-table "items"
                                   (vector (make-hash-table :test 'eql))))
                   (:non-string-key (let ((table (make-hash-table :test 'equal)))
                                      (setf (gethash :bad table) 1)
                                      table))
                   (:inline-non-string-key
                    (let ((table (%writer-table)))
                      (setf (gethash :bad table) 1)
                      (%writer-table "items" (vector 0 table))))
                   (:adjustable-vector
                    (let ((value (make-array 1 :adjustable t :fill-pointer 1
                                             :initial-contents '(1))))
                      (%writer-table "outer" (%writer-table "inner" value))))
                   (:non-table-root :not-a-table)
                   (otherwise
                    (%writer-table
                     "outer"
                     (%writer-table
                      "inner"
                      (ecase kind
                        (:nil nil)
                        (:list '(1 2))
                        (:symbol :symbol)
                        (:large-integer 9223372036854775808)))))))
              (toml-encoding-error (error) error))))
      (expect (and (typep condition 'toml-encoding-error)
                   (search expected-message
                           (toml-encoding-error-message condition))
                   (search "(value "
                           (toml-encoding-error-message condition))))
      (expect (equal expected-path (toml-encoding-error-path condition)))))
  (it "rejects an output target that is not a stream"
    (let ((condition
            (handler-case
                (progn (write-toml (%writer-table "value" 1) :not-a-stream)
                       nil)
              (type-error (error) error))))
      (expect (typep condition 'type-error))
      (expect (eq (type-error-datum condition) :not-a-stream))
      (expect (eq (type-error-expected-type condition) 'stream))))
  (it "detects cycles across table, array, inline-table, and array-table traversal"
    (labels ((encoding-error-for (value)
               (handler-case
                   (progn (encode value) nil)
                 (toml-encoding-error (condition) condition)))
             (verify-cycle (value expected-path)
               (let ((condition (encoding-error-for value)))
                 (expect (typep condition 'toml-encoding-error))
                 (expect (search "Cyclic TOML value"
                                 (toml-encoding-error-message condition)))
                 (expect (equal expected-path
                                (toml-encoding-error-path condition))))))
      (let ((table (%writer-table)))
        (setf (gethash "self" table) table)
        (verify-cycle table '("self")))
      (let ((array (make-array 1)))
        (setf (aref array 0) array)
        (verify-cycle (%writer-table "values" array) '("values" 0)))
      (let ((table (%writer-table)))
        (setf (gethash "self" table) table)
        (verify-cycle (%writer-table "values" (vector 0 table))
                      '("values" 1 "self")))
      (let ((items (make-array 1))
            (item (%writer-table)))
        (setf (aref items 0) item
              (gethash "items" item) items)
        (verify-cycle (%writer-table "items" items)
                      '("items" "items")))
      (let* ((shared (%writer-table "leaf" 1))
             (encoded (encode (%writer-table "left" shared "right" shared))))
        (expect (and (search "[left]" encoded)
                     (search "[right]" encoded))))))
  (it "enforces nesting limits consistently across tables and arrays"
    (labels ((nested-table (levels)
               (let ((root (%writer-table))
                     (parent nil))
                 (setf parent root)
                 (loop repeat levels
                       do (let ((child (%writer-table)))
                            (setf (gethash "next" parent) child
                                  parent child)))
                 (setf (gethash "leaf" parent) 1)
                 root))
             (encoding-error-for (value)
               (handler-case (progn
                               (encode value)
                               nil)
                 (toml-encoding-error (condition)
                   condition)))
             (expect-limit-error (value expected-path)
               (multiple-value-bind (limit message)
                   (cl-toml-kit::%toml-limit :nesting-depth)
                 (declare (ignore limit))
                 (let ((condition (encoding-error-for value)))
                   (expect (typep condition 'toml-encoding-error))
                   (expect
                    (string= message (toml-encoding-error-message condition)))
                   (expect
                    (equal expected-path (toml-encoding-error-path condition)))))))
      (let ((cl-toml-kit:*toml-max-nesting-depth* 2))
        (multiple-value-bind (limit message)
            (cl-toml-kit::%toml-limit :nesting-depth)
          (declare (ignore message))
          (expect (= limit 2)))
        (expect-limit-error (nested-table 3) '("next" "next" "next"))
        (expect (search "[next.next]" (encode (nested-table 2))))
        (expect
         (stringp
          (encode (%writer-table "values" (vector 0 (%writer-table "leaf" 1))))))
        (expect
         (stringp
          (encode (%writer-table "items" (vector (%writer-table "leaf" 1))))))
        (let ((cl-toml-kit:*toml-max-nesting-depth* 1))
          (expect-limit-error
           (%writer-table "values" (vector 0 (%writer-table "leaf" 1)))
           '("values" 1))
          (expect-limit-error
           (%writer-table "items" (vector (%writer-table "leaf" 1)))
           '("items")))
        (let ((cl-toml-kit:*toml-max-nesting-depth* 0))
          (expect
           (string= (format nil "flat = 1~%") (encode (%writer-table "flat" 1))))
          (expect-limit-error (%writer-table "child" (%writer-table "leaf" 1))
                              '("child"))))))
  (it "writes 1024 nested containers under the hard ceiling"
    (let ((cl-toml-kit:*toml-max-nesting-depth*
            (1+ cl-toml-kit::+toml-max-nesting-depth-ceiling+))
          (root (%writer-table))
          (parent nil))
      (setf parent root)
      (loop repeat cl-toml-kit::+toml-max-nesting-depth-ceiling+
            do (let ((child (%writer-table)))
                 (setf (gethash "next" parent) child
                       parent child)))
      (setf (gethash "leaf" parent) 1)
      (multiple-value-bind (limit message)
          (cl-toml-kit::%toml-limit :nesting-depth)
        (declare (ignore message))
        (expect (= limit
                   cl-toml-kit::+toml-max-nesting-depth-ceiling+)))
      (expect (= (1+ cl-toml-kit::+toml-max-nesting-depth-ceiling+)
                 (count #\Newline (encode root))))))
  (it "initializes context for direct writer values and TOML edits"
    (labels ((write-value-direct (value)
               (handler-case
                   (with-output-to-string (stream)
                     (cl-toml-kit::%write-value
                      value stream (make-array 8 :adjustable t :fill-pointer 0)))
                 (toml-encoding-error (condition) condition)))
             (expect-limit-error (value expected-path)
               (multiple-value-bind (limit message)
                   (cl-toml-kit::%toml-limit :nesting-depth)
                 (declare (ignore limit))
                 (let ((condition (write-value-direct value)))
                   (expect (typep condition 'toml-encoding-error))
                   (expect
                    (string= message (toml-encoding-error-message condition)))
                   (expect
                    (equal expected-path (toml-encoding-error-path condition))))))
             (expect-cycle-error (value expected-path)
               (let ((condition (write-value-direct value)))
                 (expect (typep condition 'toml-encoding-error))
                 (expect (search "Cyclic TOML value"
                                 (toml-encoding-error-message condition)))
                 (expect
                  (equal expected-path (toml-encoding-error-path condition))))))
      (let ((cl-toml-kit:*toml-max-nesting-depth* 2))
        (expect
         (stringp
          (write-value-direct (%writer-table "child" (%writer-table "leaf" 1)))))
        (expect (stringp (write-value-direct (vector (%writer-table "leaf" 1))))))
      (let ((cl-toml-kit:*toml-max-nesting-depth* 1))
        (expect-limit-error (%writer-table "child" (%writer-table "leaf" 1))
                            '("child"))
        (expect-limit-error (vector (%writer-table "leaf" 1)) '(0)))
      (let ((table (%writer-table)))
        (setf (gethash "self" table) table)
        (expect-cycle-error table '("self")))
      (let ((array (make-array 1)))
        (setf (aref array 0) array)
        (expect-cycle-error array '(0)))
      (let* ((shared (%writer-table "leaf" 1))
             (encoded
               (write-value-direct (%writer-table "left" shared "right" shared))))
        (expect (and (stringp encoded)
                     (search "left = { leaf = 1 }" encoded)
                     (search "right = { leaf = 1 }" encoded))))
      (let* ((source (%edit-test-bytes
                      (format nil "[server]~%name = ~S~%" "example")))
             (settings (%writer-table "mode" "safe"))
             (result (edit-toml source '("server" "settings") settings)))
        (expect
         (string=
          (format nil "[server]~%name = ~S~%settings = { mode = ~S }~%"
                  "example" "safe")
          (%edit-test-text result)))
        (expect
         (string= "safe"
                  (%edit-test-value result '("server" "settings" "mode")))))))
  (it "rejects surrogate code points in string values and quoted keys"
    (labels ((encoding-error-for (value)
               (handler-case
                   (progn (encode value) nil)
                 (toml-encoding-error (condition) condition)))
             (captured-output (value)
               (let ((stream (make-string-output-stream)))
                 (handler-case
                     (write-toml value stream)
                   (toml-encoding-error () nil))
                 (get-output-stream-string stream)))
             (verify-rejected (value surrogate)
               (let ((condition (encoding-error-for value))
                     (output (captured-output value)))
                 (expect (typep condition 'toml-encoding-error))
                 (expect (not (find surrogate output)))
                 (when (typep condition 'toml-encoding-error)
                   (expect
                    (string= "String contains a surrogate code point"
                             (toml-encoding-error-message condition)))
                   (expect
                    (not (find surrogate
                               (toml-encoding-error-message condition))))))))
      (dolist (surrogate (list (code-char #xd800) (code-char #xdfff)))
        (expect (characterp surrogate))
        (verify-rejected
         (%writer-table
          "value"
          (concatenate 'string "before" (string surrogate) "after"))
         surrogate)
        (verify-rejected
         (%writer-table
          (concatenate 'string "quoted " (string surrogate))
          1)
         surrogate)))))
