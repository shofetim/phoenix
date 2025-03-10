(def- state @{})

(defn lag
  `To avoid consuming too many resources when a process is broken and
  can't be kept running, we exponentially delay restarting the
  processes.`
  [name]
  (let [steps [0 1 1 2 3 5 8 13 21]
        current (get state name 0)]
    (put state name (min (inc current) 8))
    (get steps current)))

(defn reset
  `Reset the backup timer for this name`
  [name] (put state name nil))

(comment
  # Test that they march on up the steps
  (assert (= (lag :testy) 0))
  (assert (= (lag :testy) 1))
  (assert (= (lag :testy) 1))
  (assert (= (lag :testy) 2))
  (assert (= (lag :testy) 3))
  (assert (= (lag :testy) 5))
  (assert (= (lag :testy) 8))
  (assert (= (lag :testy) 13))
  (assert (= (lag :testy) 21))
  # When we are beyond the max ()lag, it should always return the max ()lag
  (assert (= (lag :testy) 21))
  # Check that it can be reset
  (assert (= (reset :testy)))
  (assert (= (lag :testy) 0)))
