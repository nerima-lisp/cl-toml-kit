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
(defun %writer-document-generator ()
  (toml-test-document-generator
   (cl-weave:gen-recursive
    (cl-weave:gen-one-of
     (cl-weave:gen-integer :min -1000 :max 1000)
     (cl-weave:gen-string
      :max-length 16
      :alphabet (toml-test-string-alphabet))
     (cl-weave:gen-member
      (list t +toml-false+ -0.0d0 1.5d0))
     (toml-test-date-generator))
    #'%writer-generated-values
    :max-depth 4)))
(defun %writer-generated-samples-match-p (samples)
  (every (lambda (document)
           (let ((encoded (encode document)))
             (handler-case
                 (toml-test-value= document (parse encoded))
               (toml-parse-error () nil))))
         samples))
(defun %writer-mutation-samples (generated-samples)
  (let ((typed-values
          (append
           (list -1000 0 1000
                 -0.0d0 1.5d0
                 sb-ext:double-float-positive-infinity
                 sb-ext:double-float-negative-infinity
                 (%writer-nan)
                 t +toml-false+
                 "quote\"slash\\"
                 (format nil "~C~C~C"
                         #\Tab #\Newline (code-char 0))
                 "café 🧪")
           (toml-test-date-values))))
    (append generated-samples
            (mapcar (lambda (value)
                      (%writer-table "value" value))
                    typed-values))))
(defun %writer-mutation-forms ()
  (let* ((package (find-package "CL-TOML-KIT"))
         (*package* package)
         (string-name (find-symbol "%WRITE-STRING-VALUE" package))
         (value-name (find-symbol "%WRITE-VALUE" package))
         (emitter-name (find-symbol "DEFINE-TOML-EMITTER" package))
         (string-form nil)
         (value-form nil))
    (with-open-file
        (stream (asdf:system-relative-pathname
                 "cl-toml-kit" "src/writer.lisp"))
      (loop for form = (read stream nil :eof)
            until (eq form :eof)
            do (cond
                ((and (consp form)
                      (eq (first form) (find-symbol "DEFUN" "COMMON-LISP"))
                      (eq (second form) string-name))
                 (setf string-form form))
                ((and (consp form)
                      (eq (first form) emitter-name)
                      (eq (second form) value-name))
                 (setf value-form (macroexpand-1 form))))))
    (unless (and string-form value-form)
      (error "Unable to read writer mutation forms."))
    (require :sb-cltl2)
    (setf (fourth value-form)
          (funcall (symbol-function
                    (find-symbol "MACROEXPAND-ALL" "SB-CLTL2"))
                   (fourth value-form)))
    (list (list string-name string-form)
          (list value-name value-form))))
;; CL-WEAVE passes the mutated form first; the descriptor is unused here.
(defun %writer-mutation-survives-p (form mutation target samples)
  (declare (ignore mutation))
  (let* ((name (gensym "WRITER-MUTANT-"))
         (definition (copy-tree form))
         (original (symbol-function target)))
    (setf (second definition) name)
    (unwind-protect
         (progn
           (handler-bind
               ((warning
                  (lambda (condition)
                    (let ((message (princ-to-string condition)))
                      (when (and
                             (search "Derived type of CL-TOML-KIT::ESCAPE is"
                                     message :test (function char-equal))
                             (search "(VALUES NULL &OPTIONAL)"
                                     message :test (function char-equal))
                             (search "conflicting with its asserted type"
                                     message :test (function char-equal))
                             (search "STRING."
                                     message :test (function char-equal)))
                        (muffle-warning condition))))))
             (eval definition))
           (setf (symbol-function target) (symbol-function name))
           (%writer-generated-samples-match-p samples))
      (setf (symbol-function target) original)
      (when (fboundp name)
        (fmakunbound name)))))
(describe "TOML writer generated input"
  (it-property "writes and parses generated values"
      ((table (%writer-document-generator)))
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
  (cl-weave:it-fuzz
   "classifies generated mutations of both production writer emitters"
   ((generated-samples
     (cl-weave:gen-list (%writer-document-generator)
                        :min-length 100 :max-length 100)))
   (:trials 1)
   (let* ((forms (%writer-mutation-forms))
          (samples (%writer-mutation-samples generated-samples))
          (value-target (find-symbol "%WRITE-VALUE" "CL-TOML-KIT"))
          (results-by-target
            (loop for (target form) in forms
                  collect
                  (cons target
                        (cl-weave:run-mutations
                         form
                         (lambda (mutated-form mutation)
                           (%writer-mutation-survives-p
                            mutated-form mutation target samples))))))
          (value-results (cdr (assoc value-target results-by-target)))
          (value-branch-tests
            (loop for result in value-results
                  for mutation = (cl-weave:mutation-result-mutation result)
                  for original = (cl-weave:mutation-original mutation)
                  when (and (consp original)
                            (symbolp (first original))
                            (string-equal (symbol-name (first original)) "IF")
                            (eq (cl-weave:mutation-operator mutation)
                                :conditional-branch))
                    collect (prin1-to-string (second original))))
          (results
            (loop for entry in results-by-target
                  append (cdr entry)))
          (summary (cl-weave:mutation-summary results)))
     (expect (= 2 (length forms)))
     (expect (= 100 (length generated-samples)))
     (expect (consp samples))
     (expect (%writer-generated-samples-match-p samples))
     (expect (consp results))
     (expect (consp value-results))
     (expect (consp value-branch-tests))
     (expect
       (every
        (lambda (branch)
          (some (lambda (test)
                  (search branch test :test (function char-equal)))
                value-branch-tests))
        (list "SIGNED-BYTE 64" "DOUBLE-FLOAT"
              "OFFSET-DATE-TIME" "LOCAL-DATE-TIME"
              "LOCAL-DATE" "LOCAL-TIME")))
     (expect (every (lambda (entry) (consp (cdr entry)))
                    results-by-target))
     (expect
       (every
        (lambda (entry)
          (plusp
           (getf (cl-weave:mutation-summary (cdr entry)) :killed)))
        results-by-target))
     (expect (plusp (getf summary :killed)))
     (expect (zerop (getf summary :survived)))
     (expect (plusp (getf summary :errored)))
     (expect (= (getf summary :total)
                (+ (getf summary :killed)
                   (getf summary :survived)
                   (getf summary :errored)))))))
