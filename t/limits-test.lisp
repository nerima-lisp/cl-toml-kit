(in-package #:cl-toml-kit/test)

(describe "TOML processing limits"
  (it "defines default nesting and input limits"
    (expect (= 256 *toml-max-nesting-depth*))
    (expect (= 16777216 *toml-max-input-bytes*))
    (expect (= 16777216 *toml-max-input-characters*)))
  (it "defines default token and path limits"
    (expect (= 256 *toml-max-number-token-length*))
    (expect (= 1024 *toml-max-path-components*)))
  (it "defines hard nesting and input ceilings"
  (expect (= 1024 cl-toml-kit::+toml-max-nesting-depth-ceiling+))
  (expect (= 1073741824 cl-toml-kit::+toml-max-input-bytes-ceiling+))
  (expect (= 67108864 cl-toml-kit::+toml-max-input-characters-ceiling+)))
  (it "defines hard token and path ceilings"
    (expect (= 4096 cl-toml-kit::+toml-max-number-token-length-ceiling+))
    (expect (= 4096 cl-toml-kit::+toml-max-path-components-ceiling+)))
  (it "defines effective default nesting and input limits"
    (expect (= 256 (cl-toml-kit::%toml-limit :nesting-depth)))
    (expect (= 16777216 (cl-toml-kit::%toml-limit :input-bytes)))
    (expect (= 16777216 (cl-toml-kit::%toml-limit :input-characters))))
  (it "defines effective default token and path limits"
    (expect (= 256 (cl-toml-kit::%toml-limit :number-token-length)))
    (expect (= 1024 (cl-toml-kit::%toml-limit :path-components))))
  (it "clamps nesting and input limits to their ceilings"
    (let ((*toml-max-nesting-depth*
            (1+ cl-toml-kit::+toml-max-nesting-depth-ceiling+))
          (*toml-max-input-bytes*
            (1+ cl-toml-kit::+toml-max-input-bytes-ceiling+))
          (*toml-max-input-characters*
            (1+ cl-toml-kit::+toml-max-input-characters-ceiling+)))
      (expect (= cl-toml-kit::+toml-max-nesting-depth-ceiling+
                 (cl-toml-kit::%toml-limit :nesting-depth)))
      (expect (= cl-toml-kit::+toml-max-input-bytes-ceiling+
                 (cl-toml-kit::%toml-limit :input-bytes)))
      (expect (= cl-toml-kit::+toml-max-input-characters-ceiling+
                 (cl-toml-kit::%toml-limit :input-characters)))))
  (it "clamps token and path limits to their ceilings"
    (let ((*toml-max-number-token-length*
            (1+ cl-toml-kit::+toml-max-number-token-length-ceiling+))
          (*toml-max-path-components*
            (1+ cl-toml-kit::+toml-max-path-components-ceiling+)))
      (expect (= cl-toml-kit::+toml-max-number-token-length-ceiling+
                 (cl-toml-kit::%toml-limit :number-token-length)))
      (expect (= cl-toml-kit::+toml-max-path-components-ceiling+
                 (cl-toml-kit::%toml-limit :path-components)))))
  (it "rejects invalid limits and accepts a zero path limit"
    (expect (signals type-error
              (let ((*toml-max-input-bytes* "256"))
                (cl-toml-kit::%toml-limit :input-bytes))))
    (expect (signals type-error
              (let ((*toml-max-nesting-depth* -1))
                (cl-toml-kit::%toml-limit :nesting-depth))))
    (expect (= 0
               (let ((*toml-max-path-components* 0))
                 (cl-toml-kit::%toml-limit :path-components)))))
  (it "selects nesting depth and message by keyword"
    (let ((*toml-max-nesting-depth* 17))
      (multiple-value-bind (limit message)
          (cl-toml-kit::%toml-limit :nesting-depth)
        (expect (= 17 limit))
        (expect (string= "TOML nesting depth limit exceeded" message)))))
  (it "selects input byte limit and message by keyword"
    (let ((*toml-max-input-bytes* 31))
      (multiple-value-bind (limit message)
          (cl-toml-kit::%toml-limit :input-bytes)
        (expect (= 31 limit))
        (expect (string= "TOML input byte limit exceeded" message)))))
  (it "selects input character limit and message by keyword"
    (let ((*toml-max-input-characters* 43))
      (multiple-value-bind (limit message)
          (cl-toml-kit::%toml-limit :input-characters)
        (expect (= 43 limit))
        (expect (string= "TOML input character limit exceeded" message)))))
  (it "selects number token limit and message by keyword"
    (let ((*toml-max-number-token-length* 59))
      (multiple-value-bind (limit message)
          (cl-toml-kit::%toml-limit :number-token-length)
        (expect (= 59 limit))
        (expect (string= "TOML number token length limit exceeded" message)))))
  (it "selects path component limit and message by keyword"
    (let ((*toml-max-path-components* 73))
      (multiple-value-bind (limit message)
          (cl-toml-kit::%toml-limit :path-components)
        (expect (= 73 limit))
        (expect (string= "TOML path component limit exceeded" message)))))
  (it "rejects unknown limit keywords"
    (expect (signals error
              (cl-toml-kit::%toml-limit :unknown-limit)))
    (expect (signals error
              (cl-toml-kit::%toml-limit-error-message :unknown-limit)))))
(progn
  (defun %table-limit-attack-source (shape)
    (let* ((target-size (* 4 1024 1024))
           (dotted-path
             (format nil "~{~A~^.~}" (make-list 249 :initial-element "a")))
           (body
             (with-output-to-string (stream)
               (dotimes (index 66)
                 (ecase shape
                   (:dotted
                    (format stream "x~D.~A.leaf = 1~%" index dotted-path))
                   (:inline
                    (format stream "x~D = {~A.leaf = 1}~%" index dotted-path))
                   (:header
                    (format stream "[x~D.~A]~%" index dotted-path)))))))
      (when (> (length body) target-size)
        (error "The table-limit test source exceeds its target size"))
      (concatenate 'string body
                   (make-string (- target-size (length body))
                                :initial-element #\#))))

  (defun %table-limit-error-message (thunk)
    (handler-case
        (progn (funcall thunk) :returned)
      (toml-parse-error (condition)
        (toml-parse-error-expected condition))))

  (describe "TOML table-count limits"
    (it "defines a default, a hard ceiling, and an effective limit"
      (expect (= 16384 *toml-max-tables*))
      (expect (= 32768 cl-toml-kit::+toml-max-tables-ceiling+))
      (expect (= 16384 (cl-toml-kit::%toml-limit :table-count))))
    (it "clamps the table-count limit to its hard ceiling"
      (let ((*toml-max-tables* (1+ cl-toml-kit::+toml-max-tables-ceiling+)))
        (expect (= cl-toml-kit::+toml-max-tables-ceiling+
                   (cl-toml-kit::%toml-limit :table-count)))))
    (it "rejects invalid values and accepts zero"
      (expect (signals type-error
                (let ((*toml-max-tables* "256"))
                  (cl-toml-kit::%toml-limit :table-count))))
      (expect (= 0
                 (let ((*toml-max-tables* 0))
                   (cl-toml-kit::%toml-limit :table-count)))))
    (it "selects the table-count error message by keyword"
      (let ((*toml-max-tables* 3))
        (multiple-value-bind (limit message)
            (cl-toml-kit::%toml-limit :table-count)
          (expect (= 3 limit))
          (expect (equal "TOML table count limit exceeded" message)))))
    (it "counts the root table"
      (let ((*toml-max-tables* 0))
        (expect (equal
                 "TOML table count limit exceeded"
                 (%table-limit-error-message (lambda () (parse "")))))))
    (it "accepts exactly the configured table count"
      (let ((*toml-max-tables* 2))
        (expect (hash-table-p (parse "x = {}")))
        (expect
         (equal
          "TOML table count limit exceeded"
          (%table-limit-error-message (lambda () (parse "x = {a = {}}")))))))
    (it "rejects deep dotted assignments with distinct roots at the default limit"
      (let* ((source (%table-limit-attack-source :dotted))
             (message
               (%table-limit-error-message (lambda () (parse source)))))
        (expect (= 4194304 (length source)))
        (expect (equal "TOML table count limit exceeded" message))))
    (it "rejects inline dotted keys with distinct roots at the default limit"
      (let* ((source (%table-limit-attack-source :inline))
             (message
               (%table-limit-error-message (lambda () (parse source)))))
        (expect (= 4194304 (length source)))
        (expect (equal "TOML table count limit exceeded" message))))
    (it "rejects deep table headers with distinct roots at the default limit"
      (let* ((source (%table-limit-attack-source :header))
             (message
               (%table-limit-error-message (lambda () (parse source)))))
        (expect (= 4194304 (length source)))
        (expect (equal "TOML table count limit exceeded" message))))
    (it "applies the default table-count limit while editing"
      (let* ((source (%table-limit-attack-source :dotted))
             (bytes (sb-ext:string-to-octets
                     source :external-format :utf-8))
             (message
               (%table-limit-error-message
                (lambda () (edit-toml bytes '("new") 1)))))
        (expect (= 4194304 (length bytes)))
        (expect (equal "TOML table count limit exceeded" message))))))
