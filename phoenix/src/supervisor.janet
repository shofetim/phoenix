(import ./crun)
(import ./backoff)
(import ./model)
(import ./util)

(def- events (ev/chan))

(defn deploy [spec]
  (let [{:name name :type type} spec
        delay (backoff/lag name)
        func (case type
               "binary" nil
               "docker" crun/deploy
               "vm" nil)]
    (when (nil? func) (print "Not yet implemented") (break))
    (ev/go
     (fiber/new
      (fn []
        (util/log "Deploying %s with delay %n" name delay)
        (ev/sleep delay)
        (func spec)) :a) nil events)))

(defn del [spec &opt restart]
  (let [{:name name :type type} spec
        func (case type
               "binary" nil
               "docker" crun/del
               "vm" nil)]
    (when (nil? func) (print "Not yet implemented") (break))
    (ev/go
     (fiber/new
      (fn []
        (util/log "Deleting %s with restart set to %s"
                  name (if restart "true" "false"))
        (func spec)
        (when restart (deploy spec))) :a) nil events)))

(defn update [spec]
  (util/log "Updating %s" (spec :name))
  (del spec true))

# todo this is not reliable yet
(defn- check-and-restart [f]
  (let [spec (fiber/last-value f)
        # todo
        _ (print "in check-and-restart the spec is:")
        _ (pp spec) # todo why is last-value sometimes empty?
        name (get spec :name)
        service (model/get-service-by-name name)]
    (when (not (empty? service))
      (util/log "Restarting %s" name)
      (deploy spec))))

(defn supervise []
  (ev/go
   (fiber/new
    (fn []
      (forever
       (def [status fiber] (ev/take events))
       (pp status)
       (case status
         :dead (check-and-restart fiber)
         :error (check-and-restart fiber)
         :ok (check-and-restart fiber)))))))

(defn start-existing-services []
  (util/log "Start existing services")
  (each sv (model/get-all-services)
    (deploy sv)))

(defn close-all []
  (util/log "Supervisor shut down all")
  (each sv (model/get-all-services)
    (del sv)))
