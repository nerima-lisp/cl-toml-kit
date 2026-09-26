;;;; Optional parser comparison benchmark.

(require :asdf)

(defpackage #:cl-toml-kit/benchmark-competitors
  (:use #:cl)
  (:export #:run-competitor-benchmarks))

(in-package #:cl-toml-kit/benchmark-competitors)

(defparameter *warmup-rounds* 2)
(defparameter *sample-count* 10)
(defparameter *sizes* '(256 512 1024))
(defparameter *clop-directory-environment-variable* "CL_TOML_KIT_CLOP_DIR")

(defun %clop-directory ()
  (let ((value (uiop:getenv *clop-directory-environment-variable*)))
    (and value (uiop:ensure-directory-pathname value))))

(defun %reader-input (size)
  (with-output-to-string (stream)
    (format stream "title = \"TOML\"~%count = 42~%active = true~%ports = [8000, 8001]~%")
    (format stream "[server]~%host = \"localhost\"~%port = 8080~%")
    (dotimes (index size)
      (format stream "key~D = ~D~%" index index))))

(defun %load-system (name)
  (handler-case
      (progn (asdf:load-system name) (values t nil))
    (error (condition)
      (values nil (format nil "~A" condition)))))

(defun %load-clop (directory)
  (if (null directory)
      (values nil "CL_TOML_KIT_CLOP_DIR is not set")
      (let ((asd (merge-pathnames "clop.asd" directory)))
        (if (not (probe-file asd))
            (values nil (format nil "missing ~A" asd))
            (handler-case
                (progn
                  (asdf:load-asd asd)
                  (%load-system "clop"))
              (error (condition)
                (values nil (format nil "~A" condition))))))))

(defun %sorted-pairs (pairs)
  (sort pairs #'string< :key #'car))

(defun %kit-normalize (value)
  (cond
    ((hash-table-p value)
     (list :table
           (%sorted-pairs
            (loop for key being the hash-keys of value using (hash-value item)
                  collect (cons key (%kit-normalize item))))))
    ((and (vectorp value) (not (stringp value)))
     (list :array (map 'list #'%kit-normalize value)))
    (t value)))

(defun %clop-table-p (value)
  (and (listp value)
       (every (lambda (item) (and (consp item) (stringp (car item)))) value)))

(defun %clop-normalize (value)
  (cond
    ((%clop-table-p value)
     (list :table
           (%sorted-pairs
            (mapcar (lambda (item)
                      (cons (car item) (%clop-normalize (cdr item)))) value))))
    ((listp value)
     (list :array (mapcar #'%clop-normalize value)))
    (t value)))

(defun %expected-value ()
  (list :table
        (list (cons "active" t)
              (cons "count" 42)
              (cons "ports" (list :array (list 8000 8001)))
              (cons "server"
                    (list :table
                          (list (cons "host" "localhost")
                                (cons "port" 8080))))
              (cons "title" "TOML"))))

(defun %parse-with (package-name function-name source &rest arguments)
  (let* ((package (find-package package-name))
         (symbol (and package (find-symbol function-name package))))
    (unless (and symbol (fboundp symbol))
      (error "~A:~A is not available" package-name function-name))
    (apply (symbol-function symbol) source arguments)))

(defun %correctness-gate (source)
  (let* ((kit (%parse-with "CL-TOML-KIT" "PARSE" source))
         (clop (%parse-with "CLOP" "PARSE" source :style :alist))
         (expected (%expected-value))
         (kit-value (%kit-normalize kit))
         (clop-value (%clop-normalize clop)))
    (unless (equal kit-value expected)
      (error "cl-toml-kit correctness gate mismatch: ~S" kit-value))
    (unless (equal clop-value expected)
      (error "clop correctness gate mismatch: ~S" clop-value))
    t))

(defun %measure-once (function)
  (sb-ext:gc :full t)
  (let ((started (get-internal-real-time))
        (before (sb-ext:get-bytes-consed)))
    (funcall function)
    (list (/ (- (get-internal-real-time) started)
             (float internal-time-units-per-second 1d0))
          (- (sb-ext:get-bytes-consed) before))))

(defun %median (values)
  (let* ((sorted (sort (copy-list values) #'<))
         (middle (floor (length sorted) 2)))
    (if (oddp (length sorted))
        (nth middle sorted)
        (/ (+ (nth (1- middle) sorted) (nth middle sorted)) 2d0))))

(defun %measure (function)
  (dotimes (round *warmup-rounds*)
    (funcall function))
  (loop repeat *sample-count* collect (%measure-once function)))

(defun %field (samples index)
  (mapcar (lambda (sample) (nth index sample)) samples))

(defun %print-measurement (name size kit-samples clop-samples)
  (let* ((kit-time (%median (%field kit-samples 0)))
         (clop-time (%median (%field clop-samples 0)))
         (kit-bytes (%median (%field kit-samples 1)))
         (clop-bytes (%median (%field clop-samples 1))))
    (format t "result~C~A~C~D~C~,6F~C~,6F~C~D~C~D~C~D~C~,6F~%"
            #\Tab name #\Tab size #\Tab kit-time #\Tab clop-time
            #\Tab (round kit-bytes) #\Tab (round clop-bytes)
            #\Tab (round (- clop-bytes kit-bytes)) #\Tab
            (if (plusp kit-bytes) (/ clop-bytes kit-bytes) 0d0))))

(defun run-competitor-benchmarks ()
  (format t "# competitor=clop warmup=~D samples=~D~%"
          *warmup-rounds* *sample-count*)
  (format t "# environment sbcl=~A implementation=~A~%"
          (lisp-implementation-version) (machine-type))
  (let ((directory (%clop-directory)))
    (multiple-value-bind (kit-loaded kit-reason) (%load-system "cl-toml-kit")
      (unless kit-loaded
        (format t "skip~Ccl-toml-kit~C~A~%" #\Tab #\Tab kit-reason)
        (return-from run-competitor-benchmarks :skipped)))
    (multiple-value-bind (clop-loaded clop-reason) (%load-clop directory)
      (unless clop-loaded
        (format t "skip~Cclop~C~A~%" #\Tab #\Tab clop-reason)
        (return-from run-competitor-benchmarks :skipped)))
    (handler-case
        (let ((gate-source (%reader-input 0)))
          (%correctness-gate gate-source)
          (format t "correctness~Cpass~Csame-input-normalized-output~%"
                  #\Tab #\Tab)
          (format t "# name~Csize~Ckit-median-seconds~Cclop-median-seconds~C"
                  #\Tab #\Tab #\Tab #\Tab)
          (format t "kit-median-bytes~Cclop-median-bytes~Callocation-delta~C"
                  #\Tab #\Tab #\Tab)
          (format t "allocation-ratio~%")
          (dolist (size *sizes*)
            (let* ((source (%reader-input size))
                   (kit-samples (%measure (lambda ()
                                            (%parse-with "CL-TOML-KIT" "PARSE" source))))
                   (clop-samples (%measure (lambda ()
                                             (%parse-with "CLOP" "PARSE" source
                                                         :style :alist)))))
              (%print-measurement "reader/parse" size kit-samples clop-samples)))
          :pass)
      (error (condition)
        (format t "failure~Cclop~C~A~%" #\Tab #\Tab condition)
        :failed))))
