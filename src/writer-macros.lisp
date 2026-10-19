(in-package #:cl-toml-kit)

(defmacro define-toml-emitter (name (value stream path))
  (let* ((value-specifications *toml-value-specifications*)
         (writer-specifications
           (loop for group in *toml-writer-emitter-specifications*
                 append (cdr group))))
    (dolist (writer-specification writer-specifications)
      (let ((kind (first writer-specification)))
        (unless (assoc kind value-specifications)
          (error 'toml-value-model-error
                 :message (format nil "Unknown TOML value kind ~S."
                                  kind)))))
    `(defun ,name (,value ,stream ,path)
       (typecase ,value
         ,@(loop for value-specification in value-specifications
                 for kind = (first value-specification)
                 for type = (second value-specification)
                 for emitter = (assoc kind writer-specifications)
                 when emitter
                   collect (if (eq kind :table)
                               `(,type
                                  (%validate-writer-table ,value ,path)
                                  ,@(rest emitter))
                               `(,type ,@(rest emitter))))
         (otherwise
          (if (integerp ,value)
              (%write-integer-value ,value ,stream ,path)
              (%signal-encoding-error "Unsupported TOML value"
                                      ,value ,path)))))))
