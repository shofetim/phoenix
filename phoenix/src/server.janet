###
### This is a fork of sport/httpf.
### Forked so we can add our own layout and static file handling
###

(import spork/ev-utils)
(import spork/htmlgen)
(import spork/http)
(import spork/schema)
(import spork/json)

(import ./http :prefix "")

# Parse the Accept header and find the first support mime type.
(def- accept-peg
  (peg/compile
    ~{:main (+
             (* '"text/html" (+ -1 ","))
             (* '"application/json" (+ -1 ","))
             (* '"application/jdn" (+ -1 ","))
             (* '"text/plain" (+ -1 ","))
             -1
             (* (thru ",") :main))}))

(defn- render-json
  [data buf]
  (json/encode data "  " "\n" buf)
  (buffer/push buf "\n"))

(defn- render-jdn
  [data buf]
  (def data (or (get data :data) data))
  (buffer/format buf "%j\n" data))

(defn- render-html
  [data buf]
  (def data (or (get data :data) data))
  (if (dictionary? data)
    (do
      (buffer/push buf "<pre><code>")
      (json/encode data "  " "\n" buf)
      (buffer/push buf "</code></pre>")
      buf)
    (buffer/push-string buf data)))

(defn- render-plain-text
  [data buf]
  (def data (or (get data :data) data))
  (assert (bytes? data))
  (buffer/push buf data))

(def- render-map
  {"text/html" render-html
   "text/plain" render-plain-text
   "application/json" render-json
   "application/jdn" render-jdn})

(defn- read-json
  [body]
  (json/decode body true))

(defn- read-jdn
  [body]
  (parse body))

(defn- read-form-data [body] (parse-body body))

(def- reader-map
  {"application/json" read-json
   "application/jdn" read-jdn
   "application/x-www-form-urlencoded" read-form-data})

(defn- make-schema-rep
  "Convert a nested object to an approximation that can
  be converted to JSON or jdn. This means no functions, cycles,
  or other objects besides primitives and built in datastructures."
  [x]
  (case (type x)
    :nil x
    :boolean x
    :number x
    :string x
    :keyword x
    :symbol x
    :array (map make-schema-rep x)
    :tuple (tuple/slice (map make-schema-rep x))
    :table (let [t @{}]
             (eachp [k v] x (put t (make-schema-rep k) (make-schema-rep v)))
             t)
    :struct (let [t @{}]
             (eachp [k v] x (put t (make-schema-rep k) (make-schema-rep v)))
             (table/to-struct t))
    (describe x)))

(defn add-route
  "Add a single manually route to a server. Prefer using `httpf/add-bindings-as-routes` for the usual case."
  [server path docstring schema handler &opt read-mime render-mime]
  (def routes (get server :routes))
  (def docs (get server :route-docs))
  (def schemas (get server :schemas))
  (def schema-sources (get server :schema-sources))
  (def mime-read-default (get server :default-mime-read))
  (def mime-render-default (get server :default-mime-render))
  (when (get routes path)
    (errorf "duplicate routes for " path))
  (put docs path docstring)
  (put routes path handler)
  (put schemas path (if schema ((schema/make-validator schema))))
  (put schema-sources path (if schema (make-schema-rep schema)))
  (put mime-read-default path read-mime)
  (put mime-render-default path render-mime)
  (if (string/has-suffix? "/" path)
    (add-route server (string/slice path 0 -2) docstring schema handler read-mime render-mime)
    server))

(defn add-bindings-as-routes
  "Add all local functions defined with :path metadata to a server. Will
  read from the :schema, :doc, :path, and :route-doc metadata to determine how
  the route behaves."
  [server &opt env]
  (default env (curenv))
  (loop [[binding meta] :pairs env
         :when (symbol? binding)
         :let [path (get meta :path)
               schema (get meta :schema)
               value (get meta :value)
               read-mime (get meta :read-mime)
               render-mime (get meta :render-mime)
               docstring (get meta :route-doc (get meta :doc))]
         :when value
         :when (bytes? path)]
    (add-route server path docstring schema value read-mime render-mime))
  server)

(defn default-payload-wrapper
  "Add some metadata to all responses"
  [payload]
  {:data payload})

(defn server
  "Create a new server."
  []
  (def routes @{})
  (def schemas @{})
  (def schema-sources @{})
  (def route-docs @{})
  (def default-mime-read @{})
  (def default-mime-render @{})
  (def wrapper default-payload-wrapper)
  (def state @{:routes routes
               :schemas schemas
               :default-mime-read default-mime-read
               :default-mime-render default-mime-render
               :schema-sources schema-sources
               :route-docs route-docs})

  (defn- generic-handler
    [req]

    (def path (get req :route (get req :path)))
    (def method (get req :method))
    (def headers (get req :headers))
    (def mime-read-default (get default-mime-read path (if (= "POST" method) "application/json" "text/html")))
    (def mime-render-default (get default-mime-render path))
    (def reader-mime (get headers "content-type" mime-read-default))
    (def reader (get reader-map reader-mime))
    # for rendering, render-mime is a hard override
    (def accepts (get headers "accept"))
    (def render-mime
      (if mime-render-default
        mime-render-default
        (if-let [res (if accepts (peg/match accept-peg accepts))]
          (get res 0 mime-read-default)
          mime-read-default)))
    (def render (get render-map render-mime render-plain-text))
    (def handler (get routes path))
    (def response-headers
      @{"content-type" render-mime })

    (defn make-response
      [code content]
      (if (or (table? content) (struct? content))
        content
        {:status code
         :headers response-headers
         :body (render (wrapper content) @"")}))

    (defn make-400-response
      [content &opt f]
      (eprint "response error: " content)
      (when f (debug/stacktrace f))
      (make-response 400 content))

    # Check static files, if none, then 404
    (unless handler
      (break (make-response 404 "not found")))

    # Check for auth
    (if-let [res (req :auth)]
      (break res))

    (try
      (do
        # Expose dynamic request in dynamic bindings
        (table/setproto req (curenv))
        (fiber/setenv (fiber/current) req)
        (setdyn :response-headers response-headers)
        (case method
          "GET" (try
                  (make-response
                    200
                    (do
                      (def query (get req :query {}))
                      (def raw-post-data (get query "data"))
                      (def post-data (if raw-post-data (parse raw-post-data)))
                      (when-let [validate (get schemas path)]
                        (validate post-data))
                      (setdyn :data post-data)
                      (handler req post-data)))
                  ([err f]
                   (make-400-response (string err) f)))
          "OPTIONS" {:status 200
                     :headers {"allow" "OPTIONS, GET, POST"
                               "content-type" render-mime
                               "server" "spork/httpf"}
                     :body (render (wrapper {:doc (get route-docs path "no docs found")
                                             :schema (get schema-sources path)}) @"")}
          "POST" (let [validate (get schemas path)
                       body (http/read-body req)
                       data (if (and body (next body))
                                (if reader
                                    (reader body)
                                    (if (multipart? req)
                                        (parse-multipart-body req)
                                        body))
                              body)]
                   (setdyn :data data)
                   (try
                     (make-response 200 (do (if validate (validate data)) (handler req data)))
                     ([err f] (make-400-response (string err) f))))
          (make-response 405 "Method not allowed. Use GET, OPTIONS, or POST.")))
    ([err f]
     (eprint "internal server error: " (string err) f)
     (debug/stacktrace (fiber/current))
     (make-response 500 err))))

  (put state :on-connection
       (fn connection-handler [conn]
         (http/server-handler
           conn
           (-> generic-handler http/logger ))))
  state)
