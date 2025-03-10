(import spork/test :prefix "")
(import /src/util)

(start-suite "Util")

(os/setenv "LOGLEVEL" "DEBUG")
(assert (= (get (capture-stdout (util/log "Hello %s %n" "Phoenix" 2)) 1) "Hello Phoenix 2\n")
        "With loglevel set to debug, we log")

(os/setenv "LOGLEVEL" "")
(assert (= (get (capture-stdout (util/log "Hello %s %n" "Phoenix" 2)) 1) "")
        "With loglevel set to other than debug, logging is silent")

(end-suite)
