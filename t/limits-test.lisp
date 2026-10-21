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
