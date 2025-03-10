(import spork/json)
(use sh)

#
# Each runtime module (binary, VM, docker/OCI) must implement a
# (deploy spec) function and a (del spec) function. Each function
# should not block. They must return spec as their last value.
#

(defn- state [name] (json/decode ($< crun state ,name) true))

(defn- update-config [spec config-name]
  (let [config (json/decode (slurp config-name) true)
        current-env (get-in config [:process :env] [])]
    (put-in config [:process :terminal] false)
    (put-in config [:process :env]
            (distinct
             (array/concat @[] current-env (get spec :env []))))
    (spit config-name (json/encode config))))

(defn- format-host-entries [links]
  (string/join
   (map (fn [{:name name :ip ip}]
          (string/format "%s %s" ip name))
          links) "\n"))

(defn- update-hosts-file [spec bundle-name]
  (let [host-file-path (string bundle-name "/rootfs/etc/hosts")
        current-hosts (slurp host-file-path)
        links (spec :links)]
    (spit host-file-path (string current-hosts (format-host-entries links) "\n"))))

(defn- add-wg-key [key bundle-name]
  (spit (string bundle-name "/tmp/wg.private") key))

(defn- veth-up [spec])

(defn- network-down [{:name name}]
  # delete the named network namespace
  ($? ip netns delete name)
  # delete the host namespace veth interface
  ($ ip link del ,(string name "0")))

(defn- network-up [spec]
  (let [name (spec :name)
        data (state name)
        pid (data :pid)]
    ($ ip netns attach ,name ,pid)
    #  call something from wg/ instead
    # (wireguard-up spec)
    (veth-up spec)
    ))


(defn deploy [spec]
  (let [{:name name :image image :env env :link link} spec
        image-name (string "/var/lib/phoenix/images/" image ".tar")
        oci-name (string "/var/lib/phoenix/containers/" image ".oci")
        bundle-name (string "/var/lib/phoenix/containers/" name ".bundle")
        config-name (string bundle-name "/config.json")]
    (when (nil? (os/stat bundle-name))
      ($ mkdir -p ,oci-name)
      ($ tar -xf ,image-name -C ,oci-name)
      ($ umoci unpack --image ,oci-name ,bundle-name)
      ($? rm -r ,oci-name)
      (update-config spec config-name)
      (update-hosts-file spec bundle-name)
      (add-wg-key (spec :private) bundle-name))
    (def proc (os/spawn ["crun" "run" "--bundle" bundle-name name] :px))
    (network-up spec)
    (os/proc-wait proc)
    (os/proc-close proc)
    spec))

(defn del [spec]
  (let [{:name name :image image} spec
        bundle-name (string "/var/lib/phoenix/containers/" image ".bundle")]
    ($? crun kill ,name 9)
    ($? rm -r ,bundle-name)
    (network-down spec)
    spec))
