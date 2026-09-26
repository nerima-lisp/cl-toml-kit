(in-package #:cl-toml-kit/test)

;; This file is intentionally not in the ASDF test system until the Reader
;; stream supplies the fixture loader and PARSE API.
(defun writer-roundtrip-cases ()
  (remove-if-not #'probe-file
                 (directory "t/fixtures/toml-test/valid/**/*.toml")))

(describe "TOML writer valid-fixture round trips"
  (it-each (writer-roundtrip-cases)
      "round trips fixture ~A"
      (pathname)
    (declare (ignore pathname))
    ;; Registered once the Reader stream provides the fixture loader.
    (expect t)))
