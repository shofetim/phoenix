(import spork/json)
(import ./db)

(def master-private-ip "fd38:dde8:32dd::1")

(defn master? []
  (-> (db/query `select whoami from local where id = 1`)
      (get-in [0 :whoami])
      (= "master")))

# todo, this only handles the first few
# spork/misc/int->string should handle the decimal->hexidecimal
# conversion, but I'm getting errors.
(defn next-machine-ip-address []
  (let [current (get-in (db/query `select max(id) as id from machines`) [0 :id])]
    (string/format "fd38:dde8:32dd::%x" (inc (or current 1)))))

(defn minion-details []
  (first
   (db/query
    `select
       whoami, "my-ip" as prvip, "my-pubip" as pubip, "my-pubkey"
     from local
     where id = 1`)))

(defn master-details []
  (merge {:master-private-ip master-private-ip}
         (first
          (db/query
           `select "master-public-key", "master-public-ip"
            from local where id = 1`))))

(defn save-keys [{:public public :private private}]
  (if (master?)
    (db/query
     `update local set "my-prikey" = ?, "my-pubkey" = ?, "master-public-key" = ?`
     [private public public])
    (db/query
     `update local set "my-prikey" = ?, "my-pubkey" = ?`
     [private public])))

(defn minion-save-init [whoami master-public-ip master-public-key pubip prvip]
  (db/query `update local set
             whoami = ?, "master-public-ip" = ?, "my-pubip" = ?,
             "master-public-key" = ?, "my-ip" = ?`
            [whoami master-public-ip pubip master-public-key prvip])
  (db/save "machines"
           {:name whoami :prvip prvip :pubip pubip :status "Accepted" :pubkey "self" }))

(defn master-save-ip [master-public-ip]
  (db/query `update local set whoami = 'master', "master-public-ip" = ?`
            [master-public-ip]))

(defn get-service-by-name [name]
  (map
   (fn [spec]
     (let [spec (struct/to-table spec)]
       (each k [:env :args :link]
       (put spec k (json/decode (spec k))))
       spec))
   (db/query
    `select s.*, m.name as 'machine-name'
     from services s
     left join machines m on s.machine = m.id
     where s.name = ?` [name])))

(defn get-by-proxyname [name]
  (db/query `select proxyname, proxyport, ip
             from services where proxyname = ?` [name]))

(defn get-all-services []
  (mapcat |(get-service-by-name ($ :name))
          (db/query `select name from services`)))

(defn get-service-by-image-name [name]
  (db/query `select * from services where image = ?` [name]))

(defn delete-service [name]
  (db/query `delete from services where name = ?` [name]))

(defn get-machine-by-name [name]
  (first (db/query `select * from machines where name = ?` [name])))

(defn get-machine-by-service-name [name]
  (first
   (db/query `select m.*
              from machines m
              left join services s on s.machine = m.id
              where s.name = ?` [name])))

(defn create-service [spec]
  (let [machine (get-machine-by-name (spec :machine))
        data (merge spec {:machine (machine :id)})]
    (try (do (db/save "services" data) nil)
         ([err fib]
          (if (= err "UNIQUE constraint failed: services.name")
            "Service already exists"
            err)))))

(defn update-service [spec]
  (let [machine (get-machine-by-name (spec :machine))
        service-name (spec :name)
        data (merge spec {:machine (machine :id)})]
    (delete-service service-name)
    (try (do (db/save "services" data) nil)
         ([err fib]
          (if (= err "UNIQUE constraint failed: services.name")
            "Service already exists"
            err)))))

(defn wg-del-route [prvip]
  (db/query `delete from wireguard where prvip = ?` [prvip]))

(defn wg-get-route [prvip]
  (first (db/query `select * from wireguard where prvip = ?` [prvip])))

(defn wg-add-route [key pubip prvip]
  (wg-del-route prvip)
  (db/save "wireguard" {:key key :pubip pubip :prvip prvip})
  (db/query `select prvip from wireguard where key = ?` [key]))

(defn expand-links
  `[name name name] -> [{
   :name    # name of service
   :public  # public wg key
   :ip      # private IP
   :minion  # minion public IP
  }]`
  [names]
  (let [col-count (length names)
        params (string/join (array/new-filled col-count "?") ",")
        sql (string/format
             `select
                s.name,
                s.public,
                s.ip,
                m.pubip as minion
              from services as s
              left join machines as m on s.machine = m.id
              where name in (%s)` params)]
    (db/query sql names)))
