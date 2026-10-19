(in-package #:cl-toml-kit/test)

(describe "edit table macro"
  (it-edit-table
    "replaces the value from ~S at path ~S"
    (("name = \"old\"~%" ("name") "" "name = \"\"~%" ""))))
