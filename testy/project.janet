(declare-project
  :name "testy"
  :description "Small binary to test supervisors"
  :dependencies ["https://github.com/janet-lang/spork"]
  :author "Jordan Schatz, Anastasija Timoscenko"
  :license "ISC"
  :version "0.1"
  :url "https://jordanschatz.com/projects/phoenix"
  :repo "https://github.com/shofetim/phoenix")

(declare-executable
  :name "testy"
  :entry "src/main.janet")
