(import uri)
(import ./helper :prefix "")

(defn- indexed-param? [str]
  (string/has-suffix? "[]" str))

(defn- body-table [all-pairs]
  (var output @{})
  (loop [[k v] :in all-pairs]
    (let [k (uri/unescape k)
          v (uri/unescape v)]
      (cond
        (indexed-param? k) (let [k (string/replace "[]" "" k)]
                             (if (output k)
                               (update output k array/concat v)
                               (put output k @[v])))
        :else (put output k v))))
  output)

(defn parse-body [str]
  (when (or (string? str)
            (buffer? str))
    (as-> (string/replace-all "+" "%20" str) ?
          (string/split "&" ?)
          (filter |(not (empty? $)) ?)
          (map |(string/split "=" $) ?)
          (body-table ?)
          (map-keys keyword ?))))

(defn format-qs [data]
  (let [parts (pairs data)]
    (string/join
     (map (fn [[k v]]
            (string (uri/escape (string k)) "=" (uri/escape (string v))))
          parts)
     "&")))

(defn content-type [request]
  (get-in request [:headers "content-type"]))

(defn multipart? [request]
  (string/has-prefix? "multipart/form-data" (content-type request)))

(def key-value '{:key (some (range "az" "AZ"))
                 :value (any (choice (range "az" "AZ" "09") (set " -_.@!#$%^&*()=~+{}[]|\\/>`<`?',\r\n\t\0")))
                 :main (sequence (<- :key) "=\"" (<- :value) "\"")})

(defn capture [str]
  (peg/compile ~(any (+ (* ,str) 1))))

(defn multipart-header [header-line]
  (let [[header-name header-value] (string/split ": " header-line)
        parts-kvs (peg/match (capture key-value) header-line)
        parts-table (table ;parts-kvs)]
    {header-name header-value
    :name (get parts-table "name")
    :filename (get parts-table "filename")}))

(defn multipart-headers [part]
  (let [index (string/find "\r\n\r\n" part)
        str (string/slice part 0 index)
        header-lines (string/split "\r\n" str)]
    (table/to-struct (apply merge (map multipart-header header-lines)))))

(defn multipart-body [part]
  (let [index (string/find "\r\n\r\n" part)
        start (+ index 4)]
    (as-> (string/slice part start) ?
          (string/trimr ? "\r\n"))))

(defn multipart [part]
  (let [headers (multipart-headers part)
        body (multipart-body part)]
    {:headers headers
      :body body}))

(defn save-part [request]
  (let [{:headers headers :body body} request
        name (get headers :name)
        filename (get headers :filename)
        content-type (content-type request)
        temp-file (when (truthy? filename) (file/temp))
        content (when (nil? temp-file) body)
        size (when (truthy? temp-file)
                (length body))
        _ (when (truthy? temp-file)
            (file/write temp-file body))]
    (when (truthy? temp-file)
      (file/seek temp-file :set))
    {:filename filename
    :name name
    :content-type content-type
    :temp-file temp-file
    :content content
    :size size}))

(defn multipart-boundary [request]
  (when-let [content-type (content-type request)
             index (string/find "boundary=" content-type)
             slice-index (+ index (length "boundary="))]
    (string/slice content-type slice-index)))

(defn parse-multipart-body [request]
  (let [boundary (multipart-boundary request)
        splitter (string "--" boundary "\r\n")
        body (as-> (get request :body) ?
                   (string/trimr ? (string "--\r\n")) ?
                   (string ? "\r\n"))]
    (as-> (string/split splitter body) ?
          (filter |(not (empty? $)) ?)
          (map multipart ?)
          (map save-part ?))))
