(in-package #:cl-toml-kit)

;; Emitter specifications reference VALUE, STREAM, and PATH directly.
(defmacro define-toml-emitter (name)
  `(defun ,name (value stream path)
     (toml-value-typecase value
       ,@(loop for (kind . forms) in *toml-writer-emitter-specifications*
               collect `(,kind ,@forms))
       (t (%write-fallback-value value stream path)))))
