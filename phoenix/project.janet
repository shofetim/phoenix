(declare-project
  :name "Phoenix"
  :description "Multi-Server Process Supervisor"
  :dependencies ["https://github.com/janet-lang/spork"
                 "https://github.com/shofetim/http"
                 "https://github.com/andrewchambers/janet-sh"
                 "https://github.com/shofetim/sqlite3"]
  :author "Jordan Schatz, Anastasija Timoscenko"
  :license "ISC"
  :version "0.1"
  :url "https://jordanschatz.com/projects/phoenix"
  :repo "https://github.com/shofetim/phoenix")

(declare-executable
  :name "phoenix"
  :entry "src/main.janet")
