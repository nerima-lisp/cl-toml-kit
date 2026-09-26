;;;; Reproducible SBCL coverage for the cl-toml-kit source system.

(require :asdf)
(require :sb-cover)

(let* ((script-directory (make-pathname :name nil :type nil :defaults *load-truename*))
       (root (truename (merge-pathnames #P"../" script-directory)))
       (deps (uiop:getenv "CL_TOML_KIT_DEPS"))
       (source-registry
         `(:source-registry
           ,@(when deps `((:tree ,(uiop:ensure-directory-pathname deps))))
           (:directory ,root)
           :ignore-inherited-configuration))
       (report-directory (uiop:ensure-directory-pathname
                          (or (uiop:getenv "CL_TOML_KIT_COVERAGE_DIR")
                              (merge-pathnames #P"coverage/" root)))))
  (asdf:initialize-source-registry source-registry)
  (declaim (optimize sb-cover:store-coverage-data))
  (sb-cover:reset-coverage)
  ;; FORCE is essential here: loading an existing FASL would omit coverage
  ;; instrumentation from the source files.
  (asdf:load-system "cl-toml-kit" :force t)
  (asdf:load-system "cl-toml-kit/test" :force t)
  (asdf:test-system "cl-toml-kit")
  (ensure-directories-exist report-directory)
  (let ((source-directory (namestring (merge-pathnames #P"src/" root))))
    (sb-cover:report
     report-directory
     :if-matches (lambda (pathname)
                   (uiop:string-prefix-p source-directory pathname))))
  (format t "Coverage report: ~A~%" report-directory))
