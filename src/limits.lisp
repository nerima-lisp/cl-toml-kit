;;;; src/limits.lisp
(in-package #:cl-toml-kit)

(defconstant +toml-max-nesting-depth-ceiling+
  1024)

(defconstant +toml-max-input-bytes-ceiling+
  1073741824)

(defconstant +toml-max-input-characters-ceiling+
  67108864)

(defconstant +toml-max-number-token-length-ceiling+
  4096)

(defconstant +toml-max-path-components-ceiling+
  4096)

(defvar *toml-max-nesting-depth*
  256
  "Maximum TOML nesting depth enforced by parsing, editing, and writing. The reader counts arrays, inline tables, and table paths; the writer counts nested arrays and tables.")

(defvar *toml-max-input-bytes*
  16777216
  "Maximum byte length accepted from files and octet vectors before decoding. Operations reject larger byte inputs.")

(defvar *toml-max-input-characters*
  16777216
  "Maximum character length accepted from strings and character streams. Operations reject longer text inputs.")

(defvar *toml-max-number-token-length*
  256
  "Maximum character length of one numeric token. Parsing rejects tokens longer than the effective limit.")

(defvar *toml-max-path-components*
  1024
  "Maximum number of components in an editor path. Editing rejects paths with more components.")

(defmacro define-toml-limits (entries)
  "Define keyword-based limit lookup and its error-message table."
  (let ((key (gensym "KEY"))
        (value (gensym "VALUE"))
        (ceiling (gensym "CEILING")))
    `(progn
       (define-toml-lookup
           %toml-limit-error-message
           ,(loop for entry in entries
                  collect `(,(first entry) ,(fourth entry)))
         :otherwise
         (error "Unknown TOML limit error key"))
       (defun %toml-limit (,key)
         "Return the effective limit and its error message; cap values above the hard ceiling and signal TYPE-ERROR for invalid values."
         (multiple-value-bind (,value ,ceiling)
             (case ,key
               ,@(loop for entry in entries
                       collect `(,(first entry)
                                  (values ,(second entry)
                                          ,(third entry))))
               (otherwise
                 (error "Unknown TOML limit key: ~S" ,key)))
           (check-type ,value (integer 0 *))
           (values (min ,value ,ceiling)
                   (%toml-limit-error-message ,key)))))))

(define-toml-limits
    ((:nesting-depth
      *toml-max-nesting-depth*
      +toml-max-nesting-depth-ceiling+
      "TOML nesting depth limit exceeded")
     (:input-bytes
      *toml-max-input-bytes*
      +toml-max-input-bytes-ceiling+
      "TOML input byte limit exceeded")
     (:input-characters
      *toml-max-input-characters*
      +toml-max-input-characters-ceiling+
      "TOML input character limit exceeded")
     (:number-token-length
      *toml-max-number-token-length*
      +toml-max-number-token-length-ceiling+
      "TOML number token length limit exceeded")
     (:path-components
      *toml-max-path-components*
      +toml-max-path-components-ceiling+
      "TOML path component limit exceeded")))
