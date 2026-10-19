(in-package #:cl-toml-kit/test)

(describe "TOML test value comparison"
  (it "distinguishes signed zero"
    (expect (not (toml-test-value= -0.0d0 0.0d0))))
  (it "distinguishes strings from vectors"
    (expect (not (toml-test-value= "" #()))))
  (it "treats NaN values as equal"
    (let ((left (gethash "value" (parse "value = nan")))
          (right (gethash "value" (parse "value = nan"))))
      (expect (toml-test-value= left right)))))
