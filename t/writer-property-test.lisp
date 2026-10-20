(in-package #:cl-toml-kit/test)
(defun %writer-invalid-value (kind amount)
  (case kind
    (:cycle
     (let ((tables
             (loop repeat amount
                   collect (make-hash-table :test 'equal))))
       (loop for table in tables
             for next in (append (rest tables) (list (first tables)))
             do (setf (gethash "next" table) next))
       (first tables)))
    (:deep
     (let ((value 1))
       (loop repeat amount
             do (setf value (%writer-table "child" value)))
       (%writer-table "value" value)))
    (:surrogate
     (let ((character (code-char amount)))
       (unless character
         (error "SBCL cannot represent surrogate code point ~X." amount))
       (%writer-table "value" (string character))))
    (otherwise
     (error "Unknown invalid-value kind ~S." kind))))
(defun %writer-expect-encoding-error (value)
  (handler-case
      (sb-ext:with-timeout 0.1
        (encode value)
        (error "Writer accepted an invalid value."))
    (toml-encoding-error () t)
    (sb-ext:timeout ()
      (error "Writer did not reject an invalid value before timeout."))))
(defun %writer-escape-cases-match-p (function)
  (and
   (every
    (lambda (case)
      (destructuring-bind (input expected) case
        (string= expected
                 (with-output-to-string (stream)
                   (funcall function input stream nil)))))
    (list
     (list "plain" "\"plain\"")
     (list " " "\" \"")
     (list (format nil "quote~Cslash~C" #\" #\\)
           "\"quote\\\"slash\\\\\"")
     (list (format nil "~C~C~C~C~C~C~C~C~C~C"
                   #\Backspace #\Tab #\Newline #\Page #\Return
                   #\" #\\ (code-char 0) (code-char 31) (code-char 127))
           "\"\\b\\t\\n\\f\\r\\\"\\\\\\u0000\\u001F\\u007F\"")
     (list (string (code-char 128))
           (format nil "\"~C\"" (code-char 128)))
     (list "café 🧪" "\"café 🧪\"")))
   (handler-case
       (progn
         (funcall function
          (string (code-char #xd800))
          (make-string-output-stream)
          nil)
         nil)
     (toml-encoding-error (condition)
       (null (toml-encoding-error-path condition)))
     (error () nil))))
(defun %writer-mutation-form ()
  (let ((*package* (find-package "CL-TOML-KIT")))
    (with-open-file
        (stream (asdf:system-relative-pathname
                 "cl-toml-kit" "src/writer.lisp"))
      (loop for form = (read stream nil :eof)
            until (eq form :eof)
            when (and (consp form)
                      (eq (first form) 'defun)
                      (eq (second form) (find-symbol "%WRITE-STRING-VALUE" "CL-TOML-KIT")))
              return form))))
;; CL-WEAVE passes the mutated form first; the descriptor is unused here.
(defun %writer-mutation-survives-p (form mutation)
  (declare (ignore mutation))
  (let* ((name (gensym "WRITER-MUTANT-"))
         (definition (copy-tree form)))
    (setf (second definition) name)
    (unwind-protect
         (progn
           (eval definition)
           (handler-case
               (%writer-escape-cases-match-p (symbol-function name))
             (error () nil)))
      (when (fboundp name)
        (fmakunbound name)))))
(describe "TOML writer generated input"
  (it-property "writes and parses generated values"
      ((table
         (toml-test-document-generator
          (cl-weave:gen-recursive
           (cl-weave:gen-one-of
            (cl-weave:gen-integer :min -1000 :max 1000)
            (cl-weave:gen-string :max-length 16)
            (cl-weave:gen-member
             (list t +toml-false+ -0.0d0 1.5d0)))
           #'%writer-generated-values
           :max-depth 4))))
    (expect (toml-test-value= table (parse (encode table)))))
  (cl-weave:it-fuzz
   "rejects cyclic tables with a TOML encoding error"
      ((size (cl-weave:gen-integer :min 1 :max 4)))
    (:trials 8 :timeout-per-trial 2)
    (%writer-expect-encoding-error
     (%writer-invalid-value :cycle size)))
  (cl-weave:it-fuzz
   "rejects deeply nested values with a TOML encoding error"
      ((depth
         (cl-weave:gen-integer
          :min (1+ *toml-max-nesting-depth*)
          :max (+ *toml-max-nesting-depth* 3))))
    (:trials 8 :timeout-per-trial 2)
    (%writer-expect-encoding-error
     (%writer-invalid-value :deep depth)))
  (cl-weave:it-fuzz
   "rejects surrogate strings with a TOML encoding error"
      ((code (cl-weave:gen-integer :min #xD800 :max #xDFFF)))
    (:trials 8 :timeout-per-trial 2)
    (%writer-expect-encoding-error
     (%writer-invalid-value :surrogate code)))
  (it "kills all generated mutations of the production string escaper"
    (let* ((form (%writer-mutation-form))
           (results (cl-weave:run-mutations
                     form #'%writer-mutation-survives-p))
           (summary (cl-weave:mutation-summary results)))
      (expect (and
               (%writer-escape-cases-match-p
                #'cl-toml-kit::%write-string-value)
               (consp results)
               (plusp (getf summary :total))))
      (expect (= 1.0 (getf summary :score)))
      (expect (and
               (= (getf summary :killed) (getf summary :total))
               (zerop (getf summary :survived))
               (zerop (getf summary :errored)))))))
