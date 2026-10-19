(in-package #:cl-toml-kit)

(defmacro define-toml-emitter (name (value stream path))
  (let ((specifications *toml-writer-emitter-specifications*)
        (value-specifications *toml-value-specifications*)
        (package (symbol-package name)))
    (labels ((handler-name (category)
               (intern (format nil "~A-~A"
                               (symbol-name name)
                               (symbol-name category))
                       package))
             (group-types (emitters)
               (mapcar (lambda (emitter)
                         (let* ((kind (first emitter))
                                (value-spec (assoc kind value-specifications)))
                           (unless value-spec
                             (error "Unknown TOML value kind ~S." kind))
                           (second value-spec)))
                       emitters)))
      `(progn
         ,@(loop for (category . emitters) in specifications
                 collect `(defun ,(handler-name category)
                              (,value ,stream ,path)
                            (toml-value-typecase ,value
                              ,@(loop for (kind . forms) in emitters
                                      collect `(,kind ,@forms)))))
         (defun ,name (,value ,stream ,path)
           (typecase ,value
             ,@(loop for (category . emitters) in specifications
                     for types = (group-types emitters)
                     for type-spec = (if (cdr types)
                                         `(or ,@types)
                                         (first types))
                     collect `(,type-spec
                               (,(handler-name category)
                                ,value ,stream ,path)))
             (otherwise
              (if (integerp ,value)
                  (%write-integer-value ,value ,stream ,path)
                  (%signal-encoding-error "Unsupported TOML value"
                                          ,value ,path)))))))))
