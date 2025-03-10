(import spork/json)
(import http)
(import ./db)
(import ./model)
(import ./wireguard :as wg)
(import ./proxy)
(use sh)

(defn- openrc-service-script [role]
  (string/format
  `#!/sbin/openrc-run
  supervisor=supervise-daemon

  name="Phoenix-%s"
  description="Multi-machine process supervisor"

  output_log="/var/log/phoenix/%s.log"
  error_log="/var/log/phoenix/%s.error"

  command=/usr/local/bin/phoenix
  command_args="start-%s"` role role role role role role))

(def- common-pkgs '@[wireguard-tools])
(def- minion-pkgs '@[crun])
(def- master-pkgs '@[uacme openssl ca-certificates rsync umoci])
(defn- install-pkgs [pkgs] ($ apk add ;pkgs))
(defn- uninstall-pkgs [pkgs] ($ apk add ;pkgs))

(defn- setup-service [role]
  (let [service-name (string "phoenix-" role)]
    (spit (string "/etc/init.d/" service-name) (openrc-service-script role))
    ($ chmod +x ,(string "/etc/init.d/" service-name))
    ($ rc-update add ,service-name default)
    ($ rc-service ,service-name start)))

(defn- hey-master-can-I-join []
  (let [master (model/master-details)
        minion (model/minion-details)
        loc (string/format "http://%s:1215/request-to-join" (master :master-public-ip))
        req (json/encode minion)]
    (http/post loc req :headers {"Content-Type" "application/json"})))

(defn master-info []
  (db/open "master")
  (let [rec (first (db/query `select * from local where id = 1`))
        {:whoami name :master-public-ip master-public-ip
         :master-public-key master-public-key :my-ip my-ip :my-pubkey my-pubkey} rec]
    (printf "Master node \n Pubkey: %s \n Public IP: %s \n Private IP: %s \n Next Machine IP: %s"
            my-pubkey master-public-ip model/master-private-ip (model/next-machine-ip-address)))
  (db/close))

(defn master [master-public-ip]
  ($ mkdir -p /srv/phoenix/registry)
  ($ mkdir -p /var/log/phoenix)
  ($ mkdir -p /var/lib/phoenix/)
  # Because we want QUIC, we need nginx's version, instead of Alpine's
  (with [out (file/open "/etc/apk/repositories" :a+)]
        (file/write out "@nginx http://nginx.org/packages/alpine/v3.21/main\n"))
  ($ wget -O /etc/apk/keys/nginx_signing.rsa.pub
     https://nginx.org/keys/nginx_signing.rsa.pub)
  (db/open "master")
  (model/master-save-ip master-public-ip)
  (install-pkgs (array/concat master-pkgs common-pkgs))
  (let [keys (wg/genkeys)
        private-ip model/master-private-ip]
    (model/save-keys keys)
    (wg/setup "master" private-ip (keys :private))
    (setup-service "master")
    (setup-service "public")
    (db/close))
  (proxy/init)
  (master-info))

(defn minion [name master-public-ip master-key pubip prvip]
  ($ mkdir -p /var/log/phoenix)
  ($ mkdir -p /var/lib/phoenix/containers)
  ($ mkdir -p /var/lib/phoenix/images)
  ($ ip link add phoenix0 type bridge)
  ($ ip addr add "10.0.0.1/8" dev phoenix0)
  ($ ip link set phoenix0 up)
  ($ sysctl -w net.ipv4.ip_forward=1)
  ($ iptables -P FORWARD ACCEPT)
  (db/open "minion")
  (model/minion-save-init name master-public-ip master-key pubip prvip)
  (install-pkgs (array/concat common-pkgs minion-pkgs))
  (let [keys (wg/genkeys)]
    (model/save-keys keys)
    (wg/setup "minion" prvip (keys :private))
    (wg/set-route "minion" master-key master-public-ip model/master-private-ip))
  ($ rc-update add cgroups)
  ($ rc-service cgroups start)
  (setup-service "minion")
  (hey-master-can-I-join)
  (db/close))

(defn cleanup []
  ($? rm -r /var/lib/phoenix/)
  ($? rm -r /var/log/phoenix/)
  ($? rm -r /srv/phoenix/registry)
  ($ sysctl -w net.ipv4.ip_forward=0)
  ($ iptables -P FORWARD DROP)
  ($? ip link del phoenix0)
  (proxy/cleanup)
  ($? rc-service cgroups stop)
  ($? rc-update del cgroups)
  (each role ["master" "public" "minion"]
    (let [service-name (string "phoenix-" role)]
      ($? rc-service ,service-name stop)
      ($? rc-update del ,service-name default)
      ($? rm ,(string "/etc/init.d/" service-name))
      (wg/down role)
      (db/destroy role))))
