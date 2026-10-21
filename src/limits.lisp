;;;; src/limits.lisp
(in-package #:cl-toml-kit)

(defmacro define-toml-limits (entries)
  "Define the limit variables, ceilings, and lookup functions from ENTRIES."
  (let ((key (gensym "KEY"))
        (value (gensym "VALUE"))
        (ceiling (gensym "CEILING")))
    `(progn
       ,@(loop for entry in entries
               collect `(defconstant ,(fourth entry) ,(fifth entry)))
       ,@(loop for entry in entries
               collect `(defvar ,(second entry)
                           ,(third entry)
                           ,(sixth entry)))
       (define-toml-lookup
           %toml-limit-error-message
           ,(loop for entry in entries
                  collect `(,(first entry) ,(seventh entry)))
         :otherwise
         (error "Unknown TOML limit error key"))
       (defun %toml-limit (,key)
         "Return the effective limit and its error message; cap values above the hard ceiling and signal TYPE-ERROR for invalid values."
         (multiple-value-bind (,value ,ceiling)
             (case ,key
               ,@(loop for entry in entries
                       collect `(,(first entry)
                                  (values ,(second entry)
                                          ,(fourth entry))))
               (otherwise
                 (error "Unknown TOML limit key: ~S" ,key)))
           (check-type ,value (integer 0 *))
           (values (min ,value ,ceiling)
                   (%toml-limit-error-message ,key)))))))

(define-toml-limits
    ((:nesting-depth
      *toml-max-nesting-depth*
      256
      +toml-max-nesting-depth-ceiling+
      1024
      "Maximum TOML nesting depth enforced by parsing, editing, and writing. The reader counts arrays, inline tables, and table paths; the writer counts nested arrays and tables."
      "TOML nesting depth limit exceeded")
     (:input-bytes
      *toml-max-input-bytes*
      16777216
      +toml-max-input-bytes-ceiling+
      1073741824
      "Maximum byte length accepted from files and octet vectors before decoding. Operations reject larger byte inputs."
      "TOML input byte limit exceeded")
     (:input-characters
      *toml-max-input-characters*
      16777216
      +toml-max-input-characters-ceiling+
      67108864
      "Maximum character length accepted from strings and character streams. Operations reject longer text inputs."
      "TOML input character limit exceeded")
     (:number-token-length
      *toml-max-number-token-length*
      256
      +toml-max-number-token-length-ceiling+
      4096
      "Maximum character length of one numeric token. Parsing rejects tokens longer than the effective limit."
      "TOML number token length limit exceeded")
     (:path-components
      *toml-max-path-components*
      1024
      +toml-max-path-components-ceiling+
      4096
      "Maximum number of components in an editor path. Editing rejects paths with more components."
      "TOML path component limit exceeded")
     (:table-count
      *toml-max-tables*
      16384
      +toml-max-tables-ceiling+
      32768
      "Maximum number of tables created while parsing one TOML document."
      "TOML table count limit exceeded")))
