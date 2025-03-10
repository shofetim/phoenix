(import spork/schema)

(def- validator
  (schema/validator
   (props
      :machine :string
      :name :string
      :image :string
      :type (enum "docker" "binary" "vm")
      :duration (or (enum "oneshot" "daemon") nil)
      :env (or :array nil)
      :proxyname (or :string nil)
      :proxyport (or :string nil)
      :healthcheck (or :string nil)
      :ip (or :string nil)
      :args (or :tuple nil)
      :link (or :tuple nil))))

(defn validate-spec [spec]
  (let [result (try (validator spec) ([err fib] err))]
    (when (= (type result) :string) result)))

(defn debug []
  (os/setenv "LOGLEVEL" "DEBUG") #todo just for manual testing
  (= (os/getenv "LOGLEVEL") "DEBUG"))

(defn log [str & rest] (when (debug) (printf str ;rest)))
