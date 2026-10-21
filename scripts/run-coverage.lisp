;;;; Coverage gate for checks.coverage.
;;;;
;;;; Run it through `nix build .#checks.aarch64-darwin.coverage` or
;;;; `nix build .#checks.x86_64-linux.coverage`, not directly:
;;;; cl-nix-forge's mkCoverageReport compiles cl-toml-kit with sb-cover
;;;; instrumentation before loading this file, then writes the HTML report to
;;;; the check output (result/cover-index.html). The gate requires at least 90%
;;;; aggregate expression and branch coverage across src/.

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

(progn
  (defparameter *minimum-percent* 90)
  ;; Reader and comment-scan floors are provisional; remeasure after the reader allocation fix lands on main.
  (defparameter *file-coverage-floors*
                '(("comment-scan.lisp" (135 136) (40 40))
                  ("conditions.lisp" (468 475) (92 92))
                  ("data.lisp" (57 115) (6 6))
                  ("edit-bytes.lisp" (197 199) (16 16))
                  ("edit-document.lisp" (319 326) (24 30))
                  ("edit-model.lisp" (107 112) (26 28))
                  ("edit-scan.lisp" (598 612) (104 112))
                  ("edit-semantic.lisp" (229 231) (38 38))
                  ("edit-splice.lisp" (479 480) (53 58))
                  ("edit.lisp" (375 385) (40 44))
                  ("limits.lisp" (1 30) :not-applicable)
                  ("package.lisp" (0 1) :not-applicable)
                  ("reader-data.lisp" (20 30) :not-applicable)
                  ("reader-document.lisp" (786 843) (90 100))
                  ("reader-macros.lisp" (7 13) :not-applicable)
                  ("reader-numbers.lisp" (654 655) (125 126))
                  ("reader-path.lisp" (27 31) (7 8))
                  ("reader-scan.lisp" (237 238) (42 44))
                  ("reader-strings.lisp" (383 388) (58 60))
                  ("reader-values.lisp" (403 409) (58 60))
                  ("reader.lisp" (348 350) (44 46))
                  ("syntax-data.lisp" (45 145) (4 4))
                  ("writer-data.lisp" (1 4) :not-applicable)
                  ("writer-macros.lisp" (4 5) :not-applicable)
                  ("writer.lisp" (419 446) (62 64)))))

(defparameter *source-directory* (merge-pathnames #P"src/" *default-pathname-defaults*))

(progn
  (defun percent (covered total)
    (when (zerop total)
      (error "Coverage total must be nonzero"))
    (* 100 (/ covered total)))
  (defun coverage-label (covered total &optional branch-p)
    (unless (and (integerp covered) (integerp total) (<= 0 covered total))
      (error "Invalid coverage count ~D/~D" covered total))
    (cond
      ((plusp total)
       (format nil "~D/~D (~,2F%)" covered total (percent covered total)))
      ((and branch-p (zerop covered)) "N/A")
      (t (error "Coverage total must be nonzero"))))
  (defun ratio-meets-floor-p (covered total floor)
    (destructuring-bind (floor-covered floor-total) floor
      (unless (and (integerp floor-covered)
                   (integerp floor-total)
                   (<= 0 floor-covered floor-total)
                   (plusp floor-total))
        (error "Invalid coverage floor ~S" floor))
      (>= (* covered floor-total) (* floor-covered total)))))

(defun print-file-statistics (files)
  (format t "~&~32A ~30A ~30A~%" "file" "expression" "branch")
  (dolist (file files)
    (destructuring-bind (&key pathname expression-covered expression-total
                           branch-covered branch-total &allow-other-keys)
        file
      (format t "~32A ~30A ~30A~%"
              (file-namestring pathname)
              (coverage-label expression-covered expression-total)
              (coverage-label branch-covered branch-total t)))))

(progn
  (defun source-file-names ()
    (mapcar #'file-namestring
            (remove-if-not
             (lambda (pathname)
               (string= (pathname-type pathname) "lisp"))
             (uiop:directory-files *source-directory*))))
  (defun enforce-file-minimums (files)
    (let* ((names (mapcar (lambda (file)
                            (file-namestring (getf file :pathname)))
                          files))
           (source-names (source-file-names))
           (floor-names (mapcar #'first *file-coverage-floors*))
           (under-floor nil))
      (when (/= (length names)
                (length (remove-duplicates names :test #'string=)))
        (error "Duplicate source filenames in coverage statistics"))
      (when (/= (length source-names)
                (length (remove-duplicates source-names :test #'string=)))
        (error "Duplicate source filenames under src/"))
      (when (/= (length floor-names)
                (length (remove-duplicates floor-names :test #'string=)))
        (error "Duplicate source filenames in coverage floors"))
      (unless (and (null (set-difference names source-names :test #'string=))
                   (null (set-difference source-names names :test #'string=)))
        (error "Coverage statistics do not match src/*.lisp files"))
      (dolist (name names)
        (unless (assoc name *file-coverage-floors* :test #'string=)
          (error "No per-file coverage floor for src/~A" name)))
      (dolist (name floor-names)
        (unless (member name names :test #'string=)
          (error "Coverage floor has no matching source file: src/~A" name)))
      (dolist (file files)
        (destructuring-bind (&key pathname expression-covered expression-total
                               branch-covered branch-total &allow-other-keys)
            file
          (let* ((name (file-namestring pathname))
                 (floor (assoc name *file-coverage-floors* :test #'string=))
                 (expression-floor (second floor))
                 (branch-floor (third floor)))
            (unless (ratio-meets-floor-p expression-covered expression-total
                                         expression-floor)
              (format t "~&src/~A expression ~,2F% is below floor ~,2F%~%"
                      name
                      (percent expression-covered expression-total)
                      (percent (first expression-floor) (second expression-floor)))
              (setf under-floor t))
            (cond
              ((and (zerop branch-covered) (zerop branch-total))
               (unless (eq branch-floor :not-applicable)
                 (error "src/~A has branch coverage 0/0 but its floor is numeric"
                        name)))
              ((eq branch-floor :not-applicable)
               (error "src/~A has a N/A branch floor but branch coverage is not 0/0"
                      name))
              ((not (ratio-meets-floor-p branch-covered branch-total branch-floor))
               (format t "~&src/~A branch ~,2F% is below floor ~,2F%~%"
                       name
                       (percent branch-covered branch-total)
                       (percent (first branch-floor) (second branch-floor)))
               (setf under-floor t))))))
      (when under-floor
        (error "One or more src/ files are below their coverage floors"))))
  (defun enforce-minimum (statistics)
    (destructuring-bind (&key expression-covered expression-total
                           branch-covered branch-total)
        statistics
      (let ((expression (percent expression-covered expression-total))
            (branch (percent branch-covered branch-total)))
        (format t "~&src/ expression ~,2F% branch ~,2F% (minimum ~D%)~%"
                expression branch *minimum-percent*)
        (when (or (< expression *minimum-percent*) (< branch *minimum-percent*))
          (error "src/ coverage is below ~D%" *minimum-percent*))))))

(handler-case
    (progn
      (asdf:test-system "cl-toml-kit")
      (let* ((include (list *source-directory*))
             (files (cl-weave:coverage-file-statistics :include-pathnames include)))
        (unless files
          (error "No src/ coverage file statistics were produced"))
        (print-file-statistics files)
        (enforce-file-minimums files)
        (enforce-minimum
         (cl-weave:coverage-statistics :include-pathnames include)))
      (uiop:quit 0))
  (error (condition)
    (format *error-output* "cl-toml-kit coverage gate failed: ~A~%" condition)
    (uiop:quit 1)))
