;;;; Coverage gate for checks.coverage.
;;;;
;;;; Run it through `nix build .#checks.<system>.coverage`, not directly:
;;;; cl-nix-forge's mkCoverageReport compiles cl-toml-kit with sb-cover
;;;; instrumentation before loading this file, and afterwards writes the HTML
;;;; report that becomes the check's output (result/cover-index.html). The
;;;; script fails when expression or branch coverage of src/ is below 90%, the
;;;; floor in the nerima-lisp organization's TEST_STANDARD.md.

(require :asdf)

(setf *default-pathname-defaults*
      (uiop:pathname-parent-directory-pathname
       (uiop:pathname-directory-pathname
        (or *load-truename* (error "Unable to determine the script location")))))

(asdf:initialize-source-registry
 `(:source-registry (:tree ,*default-pathname-defaults*) :inherit-configuration))

;; Loaded as its own top-level form so the CL-WEAVE package exists before the
;; reader reaches the forms below that name its symbols.
(asdf:load-system "cl-toml-kit/test")

(defparameter *minimum-percent* 90)

(defparameter *source-directory* (merge-pathnames #P"src/" *default-pathname-defaults*))

(defun percent (covered total)
  (when (zerop total)
    (error "Coverage total must be nonzero"))
  (* 100 (/ covered total)))

(defun print-file-statistics (files)
  (format t "~&~32A ~15@A ~15@A~%" "file" "expression" "branch")
  (dolist (file files)
    (destructuring-bind (&key pathname expression-covered expression-total
                           branch-covered branch-total &allow-other-keys)
        file
      (format t "~32A ~7D/~7D ~7D/~7D~%"
              (file-namestring pathname)
              expression-covered expression-total
              branch-covered branch-total))))

(defun enforce-minimum (statistics)
  (destructuring-bind (&key expression-covered expression-total
                         branch-covered branch-total)
      statistics
    (let ((expression (percent expression-covered expression-total))
          (branch (percent branch-covered branch-total)))
      (format t "~&src/ expression ~,2F% branch ~,2F% (minimum ~D%)~%"
              expression branch *minimum-percent*)
      (when (or (< expression *minimum-percent*) (< branch *minimum-percent*))
        (error "src/ coverage is below ~D%" *minimum-percent*)))))

(handler-case
    (progn
      (asdf:test-system "cl-toml-kit")
      (let* ((include (list *source-directory*))
             (files (cl-weave:coverage-file-statistics :include-pathnames include)))
        (unless files
          (error "No src/ coverage file statistics were produced"))
        (print-file-statistics files)
        (enforce-minimum
         (cl-weave:coverage-statistics :include-pathnames include)))
      (uiop:quit 0))
  (error (condition)
    (format *error-output* "cl-toml-kit coverage gate failed: ~A~%" condition)
    (uiop:quit 1)))
