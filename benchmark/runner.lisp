;;;; Benchmark declarations and diagnostic measurement.
(defpackage #:cl-toml-kit/benchmark
  (:use #:cl)
  (:export #:define-benchmark #:run-benchmarks))

(in-package #:cl-toml-kit/benchmark)

(defstruct benchmark
  name operation input-size thunk upper-bytes)

(defstruct benchmark-result
  benchmark status median-seconds minimum-seconds maximum-seconds
  median-bytes minimum-bytes maximum-bytes time-ratio bytes-ratio order)

(define-condition benchmark-pending (condition)
  ((reason :initarg :reason :reader benchmark-pending-reason)))

(defparameter *benchmarks* nil)
(defparameter *benchmark-warmup-rounds* 2)
(defparameter *benchmark-sample-count* 10)
(defparameter *benchmark-iterations* 10)
(defparameter *max-order-ratio* 4d0)
(defparameter *max-case-bytes* (* 256 1024 1024))

(defmacro define-benchmark (name (&key operation input-size
                                       (upper-bytes '*max-case-bytes*))
                              &body body)
  `(push (make-benchmark :name ,name :operation ,operation
                         :input-size ,input-size
                         :upper-bytes ,upper-bytes
                         :thunk (lambda () ,@body))
         *benchmarks*))

(defun %seconds (started ended)
  (/ (- ended started) (float internal-time-units-per-second 1d0)))

(defun %measure-once (benchmark)
  (sb-ext:gc :full t)
  (let ((started (get-internal-real-time))
        (before (sb-ext:get-bytes-consed)))
    (dotimes (iteration *benchmark-iterations*)
      (declare (ignore iteration))
      (funcall (benchmark-thunk benchmark)))
    (list (%seconds started (get-internal-real-time))
          (- (sb-ext:get-bytes-consed) before))))

(defun %median (values)
  (let* ((sorted (sort (copy-list values) #'<))
         (middle (floor (length sorted) 2)))
    (if (oddp (length sorted))
        (nth middle sorted)
        (/ (+ (nth (1- middle) sorted) (nth middle sorted)) 2d0))))

(defun %measure (benchmark)
  (handler-case
      (progn
        (dotimes (round *benchmark-warmup-rounds*)
          (declare (ignorable round))
          (dotimes (iteration *benchmark-iterations*)
            (declare (ignore iteration))
            (funcall (benchmark-thunk benchmark))))
        (let ((samples (loop repeat *benchmark-sample-count*
                             collect (%measure-once benchmark))))
          (flet ((field (index)
                   (mapcar (lambda (sample) (nth index sample)) samples)))
            (let ((seconds (field 0))
                  (bytes (field 1)))
              (make-benchmark-result
               :benchmark benchmark
               :status (if (<= (/ (apply #'max bytes)
                                   *benchmark-iterations*)
                              (benchmark-upper-bytes benchmark))
                           :pass
                           :upper-bound)
               :median-seconds (/ (%median seconds) *benchmark-iterations*)
               :minimum-seconds (/ (apply #'min seconds)
                                   *benchmark-iterations*)
               :maximum-seconds (/ (apply #'max seconds)
                                   *benchmark-iterations*)
               :median-bytes (/ (%median bytes) *benchmark-iterations*)
               :minimum-bytes (/ (apply #'min bytes)
                                 *benchmark-iterations*)
               :maximum-bytes (/ (apply #'max bytes)
                                 *benchmark-iterations*))))))
    (benchmark-pending (condition)
      (declare (ignore condition))
      (make-benchmark-result :benchmark benchmark :status :pending))
    (error (condition)
      (format *error-output* "benchmark ~A failed: ~A~%"
              (benchmark-name benchmark) condition)
      (make-benchmark-result :benchmark benchmark :status :error))))

(defun %ratio (new old)
  (if (plusp old) (/ new old) 0d0))

(defun %attach-order-results (results)
  (dolist (operation (remove-duplicates
                      (mapcar (lambda (result)
                                (benchmark-operation
                                 (benchmark-result-benchmark result)))
                              results)
                      :test #'equal))
    (let ((ordered
            (sort (remove-if-not
                   (lambda (result)
                     (and (eq :pass (benchmark-result-status result))
                          (equal operation
                                 (benchmark-operation
                                  (benchmark-result-benchmark result)))))
                   (copy-list results))
                  #'<
                  :key (lambda (result)
                         (benchmark-input-size
                          (benchmark-result-benchmark result))))))
      (loop for previous on ordered
            for result = (second previous)
            while result
            do (let ((time-ratio
                       (%ratio (benchmark-result-median-seconds result)
                               (benchmark-result-median-seconds
                                (first previous))))
                     (bytes-ratio
                       (%ratio (benchmark-result-median-bytes result)
                               (benchmark-result-median-bytes
                                (first previous)))))
                 (setf (benchmark-result-time-ratio result) time-ratio
                       (benchmark-result-bytes-ratio result) bytes-ratio
                       (benchmark-result-order result)
                       (if (and (<= time-ratio *max-order-ratio*)
                                (<= bytes-ratio *max-order-ratio*))
                           :pass
                           :order-failed))))))
  results)

(defun %print-result (result)
  (let ((benchmark (benchmark-result-benchmark result)))
    (format t (concatenate 'string
                           "~A~C~A~C~D~C~D~C~,6F~C~,6F~C~,6F~C~D~C~D~C~D~C~(~A~)~C~"
                           "@[~,3F~]~C~@[~,3F~]~C~(~A~)~%")
            (benchmark-name benchmark) #\Tab
            (benchmark-operation benchmark) #\Tab
            (benchmark-input-size benchmark) #\Tab
            *benchmark-sample-count* #\Tab
            (or (benchmark-result-median-seconds result) 0d0) #\Tab
            (or (benchmark-result-minimum-seconds result) 0d0) #\Tab
            (or (benchmark-result-maximum-seconds result) 0d0) #\Tab
            (if (benchmark-result-median-bytes result)
                (round (benchmark-result-median-bytes result))
                0) #\Tab
            (if (benchmark-result-minimum-bytes result)
                (round (benchmark-result-minimum-bytes result))
                0) #\Tab
            (if (benchmark-result-maximum-bytes result)
                (round (benchmark-result-maximum-bytes result))
                0) #\Tab
            (benchmark-result-status result) #\Tab
            (benchmark-result-time-ratio result) #\Tab
            (benchmark-result-bytes-ratio result) #\Tab
            (or (benchmark-result-order result) :n/a))))

(defun run-benchmarks ()
  (format t (concatenate 'string
                         "# name~Coperation~Csize~Csamples~Cmedian-seconds~C"
                         "min-seconds~Cmax-seconds~Cmedian-bytes~Cmin-bytes~C"
                         "max-bytes~Cstatus~Ctime-ratio~Cbytes-ratio~Corder~%")
                         #\Tab #\Tab #\Tab #\Tab #\Tab #\Tab #\Tab #\Tab #\Tab #\Tab
          #\Tab #\Tab #\Tab)
  (let* ((results (%attach-order-results
                   (mapcar #'%measure (nreverse *benchmarks*))))
         (failed (some (lambda (result)
                         (or (member (benchmark-result-status result)
                                     '(:error :upper-bound))
                             (eq :order-failed
                                 (benchmark-result-order result))))
                       results)))
    (dolist (result results)
      (%print-result result))
    (when failed
      (error "Benchmark limits or order checks failed"))
    t))
