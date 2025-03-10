(import spork/json)
(import spork/misc)
(import http)

(def endpoint "http://[fd38:dde8:32dd::1]:1215")

(defn- fetch [where]
  (let [res (http/get (string endpoint where))
        data (get (json/decode (res :body) true) :data)]
    data))

(defn- post [where what]
  (let [res (http/post (string endpoint where)
                       (json/encode what)
                       :headers {"Content-Type" "application/json"})
        data (get (json/decode (res :body) true) :data)]
    data))

(defn- feedback [data]
  (if (get-in data [0 :success])
     (print "Success")
     (printf "Error: %s" (get-in data [0 :error] "Unknown Error"))))

(defn waiting [] (misc/print-table (fetch "/waiting") [:name :prvip :pubip :pubkey]))

(defn services []
  (misc/print-table (fetch "/services")
                    [:machine :name :type :duration :proxyname :ip :status]))

(defn accept [name] (feedback (post "/accept" {:name name})))

(defn reject [name] (feedback (post "/reject" {:name name})))

(defn machines [] (misc/print-table (fetch "/machines") [:name :prvip :pubip :pubkey :status]))

(defn deploy [spec-name]
  (def spec (slurp spec-name))
  (json/decode spec) # if it can't parse, it will raise and inform the user here.
  (feedback (post "/deploy" {:spec spec})))

(defn del [name]
  (feedback (post "/del" {:name name})))

(defn update [spec-name]
  (def spec (slurp spec-name))
  (json/decode spec) # if it can't parse, it will raise and inform the user here.
  (feedback (post "/update" {:spec spec})))

(defn info [name]
  (let [res (post "/info" {:name name})]
    (if (empty? res)
      (print "Service not found")
      (misc/print-table res [:machine-name :name :image :type :duration
                             :proxyname :healthcheck :ip :args :link :env]))))

