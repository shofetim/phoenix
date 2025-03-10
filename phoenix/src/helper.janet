(defn map-keys
  `Executes a function on a dictionary's keys and
   returns a struct

   Example

   (map-keys snake-case {:created_at "" :uploaded_by ""}) -> {:created-at "" :uploaded-by ""}
  `
  [f dict]
  (let [acc @{}]
    (loop [[k v] :pairs dict]
      (put acc (f k) v))
    acc))

(defn- headers [req]
  (map-keys string/ascii-lower (or (req :headers) {})))

(defn- header [k req]
  (get (headers req) (string k) ""))

(def- content-type (partial header :content-type))

(defn form? [req]
  (string/has-prefix?
   "application/x-www-form-urlencoded"
   (content-type req)))

(defn redirect-to [path &opt extra-headers]
  {:status 302
   :headers (merge @{"Location" path} (or extra-headers {}))})
