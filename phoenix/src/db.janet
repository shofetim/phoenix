(import sqlite3 :as sql)
(use sh)

(var db nil)

(def- schema `
  begin;

  create table if not exists local (
     id integer primary key,
     whoami text default '',
     "master-public-ip" text default '',
     "master-public-key" text default '',
     "my-ip" text default '',
     "my-pubip" text default '',
     "my-prikey" text default '',
     "my-pubkey" text default ''
  );

  create table if not exists machines (
     id integer primary key,
     name text not null unique,
     prvip text not null,
     pubip text not null,
     pubkey text not null,
     status text not null default '' -- "Waiting" || "Accepted" || "Missing"
  );

  create table if not exists services (
    name text primary key,
    machine integer not null,
    image text not null,
    type text not null, -- 'binary', 'docker', 'vm',

    duration text not null default 'daemon', -- 'oneshot' || 'daemon'
    env text default '[]',
    proxyname text,
    proxyport text default "8000",
    healthcheck text,
    ip text,
    args text default '[]',
    link text default '[]',

    private text,
    public text,
    status text not null default '', -- 'Starting' || 'Healthy' || 'Unhealthy' || 'Stopped' || 'Deleted'

    foreign key ("machine") references "machines" ("id") on delete cascade
  );

  create table if not exists wireguard (
     prvip text primary key,
     key text,
     pubip text
  );

  commit;

  insert or ignore into local (id, whoami) values (1, '');
`)

(defn- db-name [role] (string/format "/var/lib/phoenix/%s.db" role))

(defn query [sql &opt params]
  (if params
    (sql/eval db sql params)
    (sql/eval db sql)))

(defn save [table record]
  (let [cols (keys record)
        names (string/join cols `","`)
        col-count (length cols)
        params (string/join (array/new-filled col-count "?") ",")
        sql (string/format `insert into "%s" ("%s") values (%s) returning *`
                           table names params)
        vals (map (fn [col] (record col)) cols)]
    (first (query sql vals))))

(defn open [role]
  (let [path (db-name role)]
    (set db (sql/open path))
    (query `
     pragma foreign_keys = ON;
     pragma journal_mode = WAL;
     pragma busy_timeout = 5000;
     pragma synchronous = NORMAL;
     pragma cache_size = -20000;
     pragma auto_vacuum = INCREMENTAL;
     pragma temp_store = MEMORY;`)
    (query schema)))

(defn close [] (sql/close db))

(defn destroy [role]
  (let [base-name (db-name role)
        shm (string base-name "-shm")
        wal (string base-name "-wal")]
    (each k [base-name shm wal]
      (try (os/rm ) ([_ _])))))
