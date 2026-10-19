(in-package #:cl-toml-kit)

(defun %toml-comment-string-end (source start quote multiline)
  (let ((source-length (length source))
        (position (+ start (if multiline 3 1))))
    (loop while (< position source-length)
          for char = (char source position)
          do (cond
               ((and (not multiline)
                     (member char +toml-newline-characters+ :test #'char=))
                (return position))
               ((and (char= quote +toml-double-quote+)
                     (char= char #\\))
                (incf position (if (< (1+ position) source-length) 2 1)))
               ((and multiline
                     (char= char quote)
                     (< (+ position 2) source-length)
                     (char= (char source (1+ position)) quote)
                     (char= (char source (+ position 2)) quote))
                (loop while (and (< position source-length)
                                 (char= (char source position) quote))
                      do (incf position))
                (return position))
               ((and (not multiline)
                     (char= char quote))
                (return (1+ position)))
               (t (incf position)))
          finally (return source-length))))

(defun toml-comment-spans (source)
  "Return ordered cons pairs (start . end) of 0-based string indices.
  Start is the index of #; end is exclusive and precedes a line ending (at CR in CRLF).
  Unterminated single-line strings scan to the line ending or EOF; unterminated multiline
  strings scan to EOF."
  (check-type source string)
  (let ((source-length (length source))
        (position 0)
        (spans nil))
    (loop while (< position source-length)
          for char = (char source position)
          do (cond
               ((char= char #\#)
                (let ((start position))
                  (loop while (and (< position source-length)
                                   (not (member (char source position)
                                                +toml-newline-characters+
                                                :test #'char=)))
                        do (incf position))
                  (push (cons start position) spans)))
               ((member char +toml-quote-characters+ :test #'char=)
                (let* ((quote char)
                       (multiline
                         (and (< (+ position 2) source-length)
                              (char= (char source (1+ position)) quote)
                              (char= (char source (+ position 2)) quote))))
                  (setf position
                        (%toml-comment-string-end source position quote multiline))))
               (t (incf position)))
          finally (return (nreverse spans)))))
