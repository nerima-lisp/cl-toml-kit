;;;; run-tests.lisp

(require :asdf)

(setf *default-pathname-defaults*
      (make-pathname :name nil :type nil :version nil
                     :defaults (or *load-truename*
                                   *compile-file-truename*
                                   (error "Unable to determine the script location"))))

(asdf:initialize-source-registry
 `(:source-registry
   (:tree ,*default-pathname-defaults*)
   :inherit-configuration))

(asdf:load-system "cl-weave")
(setf cl-weave:*default-timeout-ms* 10000)

(handler-case
    (progn
      (asdf:test-system "cl-toml-kit")
      (uiop:quit 0))
  (error (condition)
    (format *error-output* "cl-toml-kit test run failed: ~A~%" condition)
    (uiop:quit 1)))
