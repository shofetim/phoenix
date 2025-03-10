(import spork/httpf)
(import ./server)

(defn hello-world
  {:path "/"}
  [req data]
  [:html
     [:head [:title "Hello World"]]
     [:body [:h1 "Hello World"]]])

(def- srv (server/server))

(httpf/add-bindings-as-routes srv)

(defn daemon [] (httpf/listen srv "::" 8000))


(defn- help []
  (printf
   `testy help      Display this help text
   testy server    Run a HTTP server to respond with hello world
   testy naughty   Randomly dies and otherwise misbehaves
   testy nice      A nice reliable service`))

(defn- msg [] (print "Testy doing test."))

(defn- rng []
  (math/rng (os/time)))

(defn- random [] (math/rng-int (rng) 10))

(def- sleep-for 1)

(defn- naughty []
  (forever
   (if (> (random) 6)
     (do
       (print "Testy is dying")
       (flush)
       (os/exit))
     (msg))
   (os/sleep sleep-for)))

(defn- nice [] (forever (msg) (os/sleep sleep-for)))

(defn main [& args]
  (let [cmd (get args 1)]
    (case cmd
      "server" (daemon)
      "naughty" (naughty)
      "nice" (nice)
      "help" (help)
      (help))))
