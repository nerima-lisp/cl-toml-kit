(in-package #:cl-toml-kit)

(defmacro define-toml-emitter (name (value stream path))
  `(defun ,name (,value ,stream ,path)
     (toml-value-typecase ,value
       ,@(loop for (kind . forms) in *toml-writer-emitter-specifications*
               collect `(,kind ,@forms))
       (t (if (integerp ,value)
              (%write-integer-value ,value ,stream ,path)
              (%signal-encoding-error "Unsupported TOML value"
                                      ,value ,path))))))
