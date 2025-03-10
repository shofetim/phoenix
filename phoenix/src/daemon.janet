(import spork/httpf)
(import ./server)
(import ./api)
(import ./minion)
(import ./db)
(import ./model)
(import ./supervisor)

(def- srv (server/server))
(httpf/add-bindings-as-routes srv)

(defn shutdown-master []
  (print "Master shutting down")
  (flush)
  (db/close)
  (os/exit))

(defn start-master []
  (print "Master starting...")
  # todo, need a cron or a timer to renew acme certs
  (os/sigaction :term shutdown-master true)
  (db/open "master")
  (httpf/listen srv "fd38:dde8:32dd::1" 1215))

(defn shutdown-minion []
  (print "Minion shutting down")
  (flush)
  (supervisor/close-all)
  (db/close)
  (os/exit))

(defn start-minion []
  (print "Minion starting...")
  (os/sigaction :term shutdown-minion true)
  (db/open "minion")
  (supervisor/start-existing-services)
  (supervisor/supervise)
  (httpf/listen srv (get (model/minion-details) :prvip) 1214))
