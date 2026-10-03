(in-package #:cl-toml-kit)

(defmacro define-toml-emitter (name (value stream path))
  (let ((forms
          (loop for (kind . body) in *toml-writer-emitter-specifications*
                collect `(,kind
                           ,@(mapcar (lambda (form)
                                       (subst value 'value
                                              (subst stream 'stream
                                                     (subst path 'path form))))
                                     body)))))
    `(defun ,name (,value ,stream ,path)
       (let ((*toml-encoding-path* (%writer-error-path ,path)))
         (toml-value-typecase ,value
           ,@forms
           (t (if (integerp ,value)
                  (%write-integer-value ,value ,stream ,path)
                  (%signal-encoding-error "Unsupported TOML value"
                                          ,value ,path))))))))

(defmacro with-toml-writer-depth ((state) &body body)
  "Run BODY one aggregate level deeper, signaling a path-aware encode error."
  (let ((state-var (gensym "STATE")))
    `(let ((,state-var ,state))
       (when (and (toml-writer-state-max-depth ,state-var)
                  (>= (toml-writer-state-depth ,state-var)
                      (toml-writer-state-max-depth ,state-var)))
         (error (make-toml-encoding-error
                 :message "serialization nesting exceeds MAX-DEPTH"
                 :path (coerce (toml-writer-state-path ,state-var) 'list))))
       (incf (toml-writer-state-depth ,state-var))
       (unwind-protect (progn ,@body)
         (decf (toml-writer-state-depth ,state-var))))))
