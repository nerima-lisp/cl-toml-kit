(in-package #:cl-toml-kit/test)

(describe "TOML comment spans"
  (it-each (("line-start" "  # start" ((2 . 9)))
            ("end-of-line" "value = 1 # end" ((10 . 15)))
            ("table header" "[table] # header" ((8 . 16)))
            ("array across a newline"
             "values = [
  1, # item
  2
]"
             ((16 . 22)))
            ("EOF without newline" "answer = 42 # eof" ((12 . 17)))
            ("basic string" "value = \"x#y\" # outside" ((14 . 23)))
            ("literal string" "value = 'x#y' # outside" ((14 . 23)))
            ("multiline basic string"
             "value = \"\"\"x#y\"\"\"
# outside"
             ((18 . 27)))
            ("multiline literal string"
             "value = '''x#y'''
# outside"
             ((18 . 27)))
            ("basic quoted key" "\"key#name\" = 1 # actual" ((15 . 23)))
            ("literal quoted key" "'key#name' = 1 # actual" ((15 . 23)))
            ("Unicode before comment" "name = \"é\" # note" ((11 . 17)))
            ("unmatched opening quote" "value = \"unfinished # not comment" nil)
            ("unmatched basic quote before newline" "value = \"unfinished # in string
x = 1 # outside"
             ((38 . 47)))
            ("unmatched multiline quote through EOF" "value = \"\"\"unfinished
x = 1 # inside" nil)
            ("CRLF line endings"
             #.(format nil "a = 1 # note~C~Cb = 2 # end" #\Return #\Newline)
             ((6 . 12) (20 . 25)))
            ("escaped quote does not end a basic string"
             "value = \"a\\\"#b\" # outside"
             ((16 . 25)))
            ("trailing backslash at EOF" "value = \"unfinished\\" nil)
            ("partial multiline delimiter at EOF"
             "value = \"\"\"unfinished # inside\"\""
             nil)
            ("multiline delimiter closed at EOF"
             "value = \"\"\"inside # text\"\"\""
             nil)
            ("closed multiline delimiter exposes an EOF comment"
             "value = \"\"\"inside # text\"\"\"# outside"
             ((27 . 36))))
      "finds comment spans for ~A"
      (case-name source expected)
    (expect (equal expected (toml-comment-spans source)))))
