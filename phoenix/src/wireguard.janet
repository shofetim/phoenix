(import ./model)
(use sh)

(defn- create-private-key [] ($<_ wg genkey))

(defn- get-public-key [private-key] ($<_ echo ,private-key | wg pubkey))

(defn genkeys []
  (let [private (create-private-key)
        public (get-public-key private)]
    {:private private :public public}))

(defn create-container-interface [name ip]
  # name = service name, network namespace name
  # ip = private ip
  (let [ip-cidr (string ip "/128")
        interface (string "wgs-" name)]
    ($ ip link add ,interface type wireguard)
    ($ ip link set ,interface netns ,name)
    ($ ip -n ,name addr add ,ip-cidr dev ,interface)
    ($ ip -n ,name wg set ,interface private-key /tmp/wg.private)
    ($ ip -n ,name link set ,interface up)))

(defn insure-namespaced-peer
  [name their-pubip their-public-key their-prvip their-port]
  (let [interface (string "wgs-" name)
        ip-cidr (string my-prvip "/128")]
    ($ ip -n ,name
       wg set ,interface
         peer ,their-public-key
         endpoint ,(string their-pubip ":" their-port)
         persistent-keepalive 300
         allowed-ips ,their-prvip)
    ($ ip route add ,their-prvip dev ,interface)))

(defn setup [name ip key]
  (let [keyfile (string "/tmp/" name)
        port (if (= name "master") 40820 40821)
        name (string "wg-" name)]
    ($ ip link add ,name type wireguard)
    ($ ip addr add dev ,name ,ip)
    (spit keyfile key)
    ($ wg set ,name listen-port ,port private-key ,keyfile)
    ($ rm ,keyfile)
    ($ ip link set ,name up)))

(defn- fmt-allowed-ips [ips]
  (string/join (map (fn [r] (r :prvip)) ips) ", "))

(defn del-route [prvip]
  (let [{:key key :ips ips} (model/wg-del-route prvip)]
    ($ wg
     set peer ,key
     allowed-ips ,(fmt-allowed-ips ips))))

(defn set-route [name key pubip prvip]
  (when (model/wg-get-route prvip) (del-route prvip))
  (let [port (if (= name "master") 40821 40820)
        name (string "wg-" name)]
    ($ wg set ,name
       peer ,key
       endpoint ,(string pubip ":" port)
       allowed-ips ,(fmt-allowed-ips (model/wg-add-route key pubip prvip)))))

(defn down [name]
  ($? ip link del ,(string "wg-" name)))

(defn remove-peer [name]
  # todo
  ($ wg set wg-master peer AdmUqq/+m1B3HxhrfBv9CV9oGmR7ikEK+4hjmyZaTik= remove))

(defn insure-peer [role {:ip ip :public public}]
  (let [name (string "wg-" role)
        ip (string ip "/128")]
    ($ wg set ,name peer ,public allowed-ips ,ip)
    ($ ip route add ,ip dev ,name)))

