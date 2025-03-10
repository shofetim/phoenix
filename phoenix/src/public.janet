(import spork/httpf)
(import ./server)
(import ./db)

(defn request-to-join
  {:path "/request-to-join" :render-mime "application/json"}
  [req data]
  (db/save "machines"
           {:name (data :whoami) :prvip (data :prvip) :pubip (data :pubip)
            :pubkey (data :my-pubkey) :status "Waiting"})
  @[{:success true}])

(def- srv (server/server))
(httpf/add-bindings-as-routes srv)

(defn start []
  (db/open "master")
  (httpf/listen srv "0.0.0.0" 1215)
  (db/close))
