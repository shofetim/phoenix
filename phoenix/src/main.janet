(import ./daemon)
(import ./setup)
(import ./cli)
(import ./public)

(defn help []
  (print
   `phoenix help — Display this help text

   === Setup ===
   phoenix master <public-ip> — Setup & start master
   phoenix master-info   — Retrieve information about the master node
   phoenix minion <name> <master-public-ip> <master-key> <minion-public-ip> <minion-private-ip>  — Setup & start minion
   phoenix start-master  — Start the API daemon
   phoenix start-minion  — Start the API daemon
   phoenix cleanup       — Uninstall minion/master and clean up resources used

   === System ===
   phoenix waiting       — List machines waiting to join cluster
   phoenix machines      — List all machines
   phoenix accept <name> — Accept machine <name> to the cluster
   phoenix reject <name> — Reject machine <name> from cluster
   phoenix services      — List all supervised services

   === Services ===
   phoenix deploy <spec.json>     — Run & Supervise process specified in <spec.json>
   phoenix update <spec.json>     — Update & Restart process specified in <spec.json>
   phoenix del <service-name>     — Delete identified process
   phoenix info <service-name>    — Detail information about service-name>

`))

(defn main [& args]
  (let [cmd (get args 1)
        arguments (array/slice args (min 2 (length args)))
        first-arg (first arguments)]
    (cond
      # === Setup ===
      (= cmd "master") (setup/master ;arguments)    # ✓
      (= cmd "master-info") (setup/master-info)     # ✓
      (= cmd "minion") (setup/minion ;arguments)    # ✓
      (= cmd "start-master") (daemon/start-master)  # ✓
      (= cmd "start-public") (public/start)         #
      (= cmd "start-minion") (daemon/start-minion)  # ✓
      (= cmd "cleanup") (setup/cleanup)             # ✓

      # === System ===
      (= cmd "waiting") (cli/waiting)               # ✓
      (= cmd "machines") (cli/machines)             # ✓
      (= cmd "accept") (cli/accept first-arg)       # ✓
      (= cmd "reject") (cli/reject first-arg)       # ✓
      (= cmd "services") (cli/services)             # ✓

      # === Services ===
      (= cmd "deploy") (cli/deploy first-arg)       # ½
      (= cmd "update") (cli/update first-arg)       # ½
      (= cmd "del") (cli/del first-arg)             # ½
      (= cmd "info") (cli/info first-arg)           # ✓

      (= cmd "help") (help)
      (help))))
