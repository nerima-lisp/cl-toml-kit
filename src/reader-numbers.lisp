(in-package #:cl-toml-kit)
(define-toml-character-class %toml-decimal-point-p (#\.))

(defun %float-token-p (source start end)
  (let ((prefix (and (< (+ start 1) end)
                     (char= (char source start) #\0)
                     (%toml-integer-base (char-downcase (char source (1+ start)))))))
    (and (not prefix)
         (or (loop for index from start below end
                   thereis (%toml-decimal-point-p (char source index)))
             (loop for index from start below end
                   thereis (%toml-exponent-marker-p (char source index)))))))

(defun %date-shaped-p (source start end)
  (or (and (>= (- end start) 10)
           (loop for index below 4
                 always (toml-decimal-character-p (char source (+ start index))))
           (eq (%toml-date-separator-kind (char source (+ start 4))) :date))
      (and (>= (- end start) 5)
           (toml-decimal-character-p (char source start))
           (toml-decimal-character-p (char source (1+ start)))
           (eq (%toml-date-separator-kind (char source (+ start 2))) :time))))

(defun %local-date-shaped-p (text)
  (and (= (length text) 10)
       (loop for index below 4
             always (toml-decimal-character-p (char text index)))
       (eq (%toml-date-separator-kind (char text 4)) :date)
       (loop for index from 5 below 7
             always (toml-decimal-character-p (char text index)))
       (eq (%toml-date-separator-kind (char text 7)) :date)
       (loop for index from 8 below 10
             always (toml-decimal-character-p (char text index)))))

(defun %token-equal-p (source start end token)
  (and (= (- end start) (length token))
       (loop for index below (length token)
             always (char= (char source (+ start index)) (char token index)))))

(defun %parse-date-value (state start end success failure)
  (let* ((text (subseq (toml-reader-state-source state) start end))
         (value
          (handler-case
              (cond
               ((and (> (length text) 10)
                     (%toml-date-time-separator-p (char text 10))
                     (%date-time-offset-p text))
                (cl-date-kit:parse-offset-date-time text :profile :rfc3339))
               ((and (> (length text) 10)
                     (%toml-date-time-separator-p (char text 10)))
                (cl-date-kit:parse-local-date-time text :profile :rfc3339))
               ((%local-date-shaped-p text)
                (cl-date-kit:parse-local-date text))
               (t (cl-date-kit:parse-local-time text :profile :rfc3339)))
            (cl-date-kit:cl-date-kit-error ()
                                           (funcall failure start :valid-date-or-time nil)
                                           (return-from %parse-date-value nil)))))
    (funcall success value end)))

(defun %date-time-offset-p (text)
  (let ((index 16)
        (length (length text)))
    (when (and (> length index)
               (%toml-date-time-separator-p (char text 10)))
      (when (eq (%toml-date-separator-kind (char text index)) :time)
        (incf index 3))
      (when (and (< index length) (eq (%toml-date-separator-kind (char text index)) :fraction))
        (incf index)
        (loop while (and (< index length)
                         (digit-char-p (char text index)))
              do (incf index)))
      (and (< index length)
           (%toml-date-time-offset-marker-p (char text index))))))

(defun %parse-float-significand (state position end success failure)
  (let ((index position) (mantissa 0) (fraction 0)
        (seen-dot nil) (previous-digit nil))
    (loop while (< index end)
          for char = (%source-char state index)
          do (cond
              ((and (not seen-dot) (%toml-decimal-point-p char))
               (unless previous-digit
                 (funcall failure index :fraction-digit nil)
                 (return-from %parse-float-significand nil))
               (setf seen-dot t previous-digit nil))
              ((%toml-exponent-marker-p char)
               (unless previous-digit
                 (funcall failure index :exponent-digit nil)
                 (return-from %parse-float-significand nil))
               (funcall success (list mantissa fraction index) index)
               (return-from %parse-float-significand nil))
              ((char= char #\_)
               (unless previous-digit
                 (funcall failure index :digit-between-underscores nil)
                 (return-from %parse-float-significand nil))
               (setf previous-digit nil))
              (t
               (let ((digit (digit-char-p char 10)))
                 (unless digit
                   (funcall failure index :float-digit nil)
                   (return-from %parse-float-significand nil))
                 (setf mantissa (+ (* mantissa 10) digit)
                       previous-digit t)
                 (when seen-dot (incf fraction)))))
          (incf index))
    (unless previous-digit
      (funcall failure end :float-digit nil)
      (return-from %parse-float-significand nil))
    (funcall success (list mantissa fraction nil) end)))

(defun %parse-float-exponent (state position end success failure)
  (let ((index (1+ position)) (negative nil) (exponent 0)
        (previous-digit nil))
    (when (%toml-numeric-sign-p (%source-char state index))
      (setf negative (char= (%source-char state index) #\-))
      (incf index))
    (loop while (< index end)
          for char = (%source-char state index)
          do (if (char= char #\_)
                 (progn
                   (unless previous-digit
                     (funcall failure index :digit-between-underscores nil)
                     (return-from %parse-float-exponent nil))
                   (setf previous-digit nil))
               (let ((digit (digit-char-p char 10)))
                 (unless digit
                   (funcall failure index :exponent-digit nil)
                   (return-from %parse-float-exponent nil))
                 (setf exponent (+ (* exponent 10) digit)
                       previous-digit t)))
          (incf index))
    (unless previous-digit
      (funcall failure end :exponent-digit nil)
      (return-from %parse-float-exponent nil))
    (funcall success (if negative (- exponent) exponent) end)))

(defun %finish-float-range (state start mantissa fraction exponent negative end
                                  success failure)
  (when negative (setf mantissa (- mantissa)))
  (handler-case
      (let ((value (coerce (* mantissa (expt 10 (- exponent fraction)))
                           'double-float)))
        (when (and (not (zerop mantissa)) (zerop value))
          (funcall failure start :representable-finite-float nil)
          (return-from %finish-float-range nil))
        (funcall success value end))
    (floating-point-overflow ()
                             (funcall failure start :representable-finite-float nil))))

(defun %parse-float-range (state start end success failure)
  (let ((index start) (negative nil))
    (when (%toml-numeric-sign-p (%source-char state index))
      (setf negative (char= (%source-char state index) #\-))
      (incf index))
    (when (and (char= (%source-char state index) #\0)
               (< (1+ index) end)
               (or (toml-decimal-character-p (%source-char state (1+ index)))
                   (char= (%source-char state (1+ index)) #\_)))
      (funcall failure (1+ index) :no-leading-zero nil)
      (return-from %parse-float-range nil))
    (%parse-float-significand
     state index end
     (lambda (significand next)
       (declare (ignore next))
       (let ((marker (third significand)))
         (if marker
             (%parse-float-exponent
              state marker end
              (lambda (exponent exponent-end)
                (declare (ignore exponent-end))
                (%finish-float-range
                 state start (first significand) (second significand)
                 exponent negative end success failure))
              failure)
           (%finish-float-range
            state start (first significand) (second significand)
            0 negative end success failure))))
     failure)))

(defun %parse-integer-digits
    (state error-position position end base negative success failure)
  (let ((index position) (value 0) (digits 0)
        (previous-digit nil) (leading-zero nil))
    (loop while (< index end)
          for char = (%source-char state index)
          do (if (char= char #\_)
                 (progn
                   (unless previous-digit
                     (funcall failure index :digit-between-underscores nil)
                     (return-from %parse-integer-digits nil))
                   (setf previous-digit nil))
               (let ((digit (digit-char-p char base)))
                 (unless digit
                   (funcall failure index :integer-digit nil)
                   (return-from %parse-integer-digits nil))
                 (when (and (= base 10) (zerop digits) (zerop digit))
                   (setf leading-zero t))
                 (when (and leading-zero (= digits 1))
                   (funcall failure index :no-leading-zero nil)
                   (return-from %parse-integer-digits nil))
                 (setf value (+ (* value base) digit)
                       previous-digit t)
                 (incf digits)))
          (incf index))
    (unless (and (> digits 0) previous-digit)
      (funcall failure end :integer-digit nil)
      (return-from %parse-integer-digits nil))
    (setf value (if negative (- value) value))
    (unless (%toml-integer-in-range-p value)
      (funcall failure error-position :signed-64-bit-integer nil)
      (return-from %parse-integer-digits nil))
    (funcall success value end)))

(defun %parse-integer-range (state start end success failure)
  (let ((index start) (negative nil) (signed nil))
    (when (%toml-numeric-sign-p (%source-char state index))
      (setf negative (char= (%source-char state index) #\-)
            signed t)
      (incf index))
    (when (and (= (1+ index) end)
               (char= (%source-char state index) #\0))
      (funcall success 0 end)
      (return-from %parse-integer-range nil))
    (when (and (< (1+ index) end)
               (char= (%source-char state index) #\0)
               (%toml-integer-base (%source-char state (1+ index))))
      (when signed
        (funcall failure start :unsigned-prefixed-integer nil)
        (return-from %parse-integer-range nil))
      (%parse-integer-digits
       state start (+ index 2) end
       (%toml-integer-base (%source-char state (1+ index)))
       nil success failure)
      (return-from %parse-integer-range nil))
    (%parse-integer-digits state start index end 10 negative success failure)))
