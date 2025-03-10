(import ./model)
(import ./supervisor)

(def- success @[{:success true}])

(defn deploy
  {:path "/minion/deploy" :render-mime "application/json"}
  [req data]
  (let [spec (data :spec)]
    (model/create-service spec)
    (supervisor/deploy spec)
    success))

(defn update
  {:path "/minion/update" :render-mime "application/json"}
  [req data]
  (let [spec (data :spec)]
    (model/update-service spec)
    (supervisor/update spec)
    success))

(defn del
  {:path "/minion/del" :render-mime "application/json"}
  [req data]
  (let [spec (data :spec)]
    (model/delete-service (spec :name))
    (supervisor/del spec)
    success))
