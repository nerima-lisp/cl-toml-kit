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
  ;; This inner timeout must beat the CL-Weave limit, which skips timed-out trials.
  (or
   (handler-case
       (progn
         (sb-ext:with-timeout 5
           (encode value))
         nil)
     (sb-ext:timeout ()
       (error "TOML writer fuzz trial timed out while encoding an invalid value."))
     (toml-encoding-error () t)
     (serious-condition (condition)
       (error "TOML writer fuzz trial raised unexpected condition ~A: ~A"
              (type-of condition) condition)))
   (error "Writer accepted an invalid value.")))
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
           (handler-case
               (toml-test-value= document (parse (encode document)))
             (error () nil)))
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
  (it "writes documents at the configured nesting limit"
    (let* ((root (%writer-table))
           (parent root))
      (loop repeat *toml-max-nesting-depth*
            do (let ((child (%writer-table)))
                 (setf (gethash "next" parent) child
                       parent child)))
      (setf (gethash "leaf" parent) 1)
      (expect (toml-test-value= root (parse (encode root))))))
  (cl-weave:it-fuzz
   "rejects cyclic tables with a TOML encoding error"
      ((size (cl-weave:gen-integer :min 1 :max 4)))
    (:trials 8 :timeout-per-trial 8)
    (%writer-expect-encoding-error
     (%writer-invalid-value :cycle size)))
  (cl-weave:it-fuzz
   "rejects deeply nested values with a TOML encoding error"
      ((depth
         (cl-weave:gen-integer
          :min (1+ *toml-max-nesting-depth*)
          :max (+ *toml-max-nesting-depth* 3))))
    (:trials 8 :timeout-per-trial 8)
    (%writer-expect-encoding-error
     (%writer-invalid-value :deep depth)))
  (cl-weave:it-fuzz
   "rejects surrogate strings with a TOML encoding error"
      ((code (cl-weave:gen-integer :min #xD800 :max #xDFFF)))
    (:trials 8 :timeout-per-trial 8)
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
          (branch-specifications
            (let ((*package* (find-package "CL-TOML-KIT")))
              (list
               (cons :integer
                     (read-from-string "(typep :value '(signed-byte 64))"))
               (cons :float
                     (read-from-string "(typep :value 'double-float)"))
               (cons :offset-date-time
                     (read-from-string
                      "(typep :value 'cl-date-kit:offset-date-time)"))
               (cons :local-date-time
                     (read-from-string
                      "(typep :value 'cl-date-kit:local-date-time)"))
               (cons :local-date
                     (read-from-string
                      "(typep :value 'cl-date-kit:local-date)"))
               (cons :local-time
                     (read-from-string
                      "(typep :value 'cl-date-kit:local-time)")))))
          (results-by-target
            (loop for (target form) in forms
                  collect
                  (cons target
                        (cl-weave:run-mutations
                         form
                         (lambda (mutated-form mutation)
                           (handler-case
                             (sb-ext:with-timeout 0.5
                               (%writer-mutation-survives-p
                                mutated-form mutation target samples))
                           (sb-ext:timeout () nil)))))))
          (value-results (cdr (assoc value-target results-by-target)))
          (branch-results
            (loop for result in value-results
                  for mutation =
                    (cl-weave:mutation-result-mutation result)
                  for original = (cl-weave:mutation-original mutation)
                  for condition =
                    (when (and (eq (cl-weave:mutation-operator mutation)
                                   :conditional-branch)
                               (consp original)
                               (eq (first original) 'if))
                      (second original))
                  for normalized =
                    (when (and (consp condition)
                               (eq (first condition) 'typep)
                               (= (length condition) 3)
                               (symbolp (second condition)))
                      (list (first condition) :value (third condition)))
                  for expected =
                    (find normalized branch-specifications
                          :key (function cdr)
                          :test (function equal))
                  when expected
                    collect (cons (first expected) result)))
          (results (loop for entry in results-by-target
                         append (cdr entry)))
          (summary (cl-weave:mutation-summary results)))
     (expect (= 2 (length forms)))
     (expect (%writer-generated-samples-match-p samples))
     (expect
      (every
       (lambda (entry)
         (let* ((target-summary
                  (cl-weave:mutation-summary (cdr entry)))
                (total (getf target-summary :total)))
           (and (plusp total)
                (= total (getf target-summary :killed))
                (zerop (getf target-summary :survived))
                (zerop (getf target-summary :errored)))))
       results-by-target))
     (expect
      (every
       (lambda (specification)
         (let ((matches
                 (remove-if-not
                  (lambda (entry)
                    (eq (car specification) (car entry)))
                  branch-results)))
           (and (= 1 (length matches))
                (eq :killed
                    (cl-weave:mutation-result-status
                     (cdr (first matches)))))))
       branch-specifications))
     (expect (= 16 (getf summary :total)))
     (expect (= (getf summary :total)
                (getf summary :killed)))
     (expect (zerop (getf summary :survived)))
     (expect (zerop (getf summary :errored))))))
