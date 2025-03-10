(import spork/json)
(import http)
(import ./db)
(import ./model)
(import ./util)
(import ./wireguard :as wg)
(import ./proxy)

(def- err @[{:success false}])
(defn- make-error [err] @[{:success false :error (or err "Unknown")}])
(def- success @[{:success true}])

(defn- send-to-minion [where what]
  (let [machine-name (get-in what [:spec :machine-name]
                             (get-in what [:spec :machine]))
        machine (model/get-machine-by-name machine-name)
        _ (when (nil? machine) (print "Minion node doesn't exist")(break))
        endpoint (string/format "http://[%s]:1214/minion" (machine :prvip))]
    (http/post (string endpoint where)
               (json/encode what)
               :headers {"Content-Type" "application/json"})))

(defn waiting
  {:path "/waiting" :render-mime "application/json"}
  [req data]
  (db/query `select name, pubip, prvip, pubkey
             from machines where status = 'Waiting'`))

(defn services
  {:path "/services" :render-mime "application/json"}
  [req data]
  (let [sql `select
               m.name as machine,
               s.name,
               s.image,
               s.type,
               s.duration,
               s.env,
               s.proxyname,
               s.healthcheck,
               s.ip,
               s.args,
               s.link,
               s.status
             from services as s
             left join machines as m on s.machine = m.id
             where m.status = 'Accepted'`
        res (db/query sql)]
    res))

(defn accept
  {:path "/accept" :render-mime "application/json"}
  [req data]
  (db/query `update machines set status = 'Accepted' where name = ?`
            [(data :name)])
  (let [machine (model/get-machine-by-name (data :name))]
    (wg/set-route "master" (machine :pubkey) (machine :pubip) (machine :prvip)))
  success)

(defn reject
  {:path "/reject" :render-mime "application/json"}
  [req data]
  (db/query `delete from machines where name = ?` [(data :name)])
  success)

(defn machines
  {:path "/machines" :render-mime "application/json"}
  [req data]
  (db/query `select name, prvip, pubip, pubkey, status from machines`))

(defn deploy
  {:path "/deploy" :render-mime "application/json"}
  [req data]
  (let [spec (json/decode (data :spec) true)
        malformed (util/validate-spec spec)
        spec (merge spec (wg/genkeys) (model/expand-links (spec :link)))
        error-on-save (when (not malformed) (model/create-service spec))]
    (cond
      malformed (make-error malformed)
      error-on-save (make-error error-on-save)
      (do
        (when-let [proxyname (spec :proxyname)] (proxy/service-up proxyname))
        (wg/insure-peer "master" spec)
        (send-to-minion "/deploy" {:spec spec})
        success))))

(defn del
  {:path "/del" :render-mime "application/json"}
  [req data]
  (let [name (data :name)
        service (first (model/get-service-by-name name))]
    (when-let [name (service :proxyname)] (proxy/service-down name))
    (send-to-minion "/del" {:spec service})
    (wg/remove-peer name)
    (model/delete-service name)
    success))

(defn update
  {:path "/update" :render-mime "application/json"}
  [req data]
  (let [spec (json/decode (data :spec) true)
        malformed (util/validate-spec spec)
        _ (when (empty? (model/get-service-by-name (spec :name)))
            (break (make-error "Service doesn't exist")))
        _ (proxy/if-up-down (spec :name))
        error-on-save (when (not malformed) (model/update-service spec))]
    # todo handle when the update is a move between minions.
    (send-to-minion "/update" {:spec spec})
    (cond
      malformed (make-error malformed)
      error-on-save (make-error error-on-save)
      (when-let [proxyname (spec :proxyname)]
        (proxy/service-up proxyname)
        success))))

(defn info
  {:path "/info" :render-mime "application/json"}
  [req data]
  (let [res (model/get-service-by-name (data :name))]
    res))
