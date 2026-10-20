(in-package #:cl-toml-kit/test)
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
  ;; Bound recursive parser depth by keeping generated strings short.
  (cl-weave:it-fuzz
   "returns a value or a TOML error for generated strings"
      ((source (cl-weave:gen-string
               :max-length 96
               :alphabet
               (concatenate
                'string
                "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 #=[]{},.+-_:"
                (map 'string #'code-char
                     '(0 1 9 10 13 31 127 34 39 92))))))
    (:trials 40 :timeout-per-trial 2)
    (handler-case
        (expect (hash-table-p (parse source)))
      (toml-kit-error () nil))))
