(use sh)
(import ./model)
(import ./util)

(def- nginx-conf
  `
  user  nginx;
  worker_processes  auto;

  error_log  /var/log/nginx/error.log notice;
  pid        /var/run/nginx.pid;

  events {
    worker_connections  1024;
  }

  http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    client_max_body_size 10m;

    log_format json escape=json '{'
        '"timestamp":"$time_iso8601",'       # timestamp
        '"method":"$request_method",'        # method
        '"URI":"$uri",'                      # URI
        '"hostname":"$host",'                # Hostname
        '"query":"$query_string",'           # query string
        '"status":"$status",'                # status
        '"remoteip":"$remote_addr",'         # remote IP address
        '"useragent":"$http_user_agent",'    # user agent
        '"requesttime":"$request_time",'     # request time
        '"bytes":"$body_bytes_sent",'        # body bytes sent
        '"referrer":"$http_referer"'         # referrer
    '}';

    access_log /var/log/nginx/access.log json;
    sendfile        on;
    keepalive_timeout  65;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ecdh_curve X25519:prime256v1:secp384r1;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers off;

    ssl_session_timeout 1d;
    ssl_session_cache shared:MozSSL:10m;  # about 40000 sessions

    include /etc/nginx/conf.d/*.conf;
  }`)

(def- default-server
  `
  # redirect all http -> https, except for acme
  server {
    listen 80 default_server;
    server_name _;

    location / {
      return 301 https://$host$request_uri;
    }

    location /.well-known/acme-challenge/ {
      root /srv/acme;
    }
  }`)

(defn- upstream-server-block
  `[{:ip "string representation of IP" :proxyport "port as string"}] -> nginx config`
  [upstream-servers]
  (string/join
   (map (fn [{:ip ip :proxyport proxyport}]
          (string/format "server [%s]:%s;\n     " ip proxyport))
        upstream-servers)
   "\n"))

(defn- slug [name] (string/replace-all "." "_" name))

(defn- service-template [server-name upstream-servers]
  (string/format
   `
   upstream %s_backend {
     zone upstreams 64K;
     %s
     least_conn;
     keepalive 5;
   }
   server {
     server_name %s;

     listen 443 quic;
     listen [::]:443 quic;
     listen 443 ssl;
     listen [::]:443 ssl;

     ssl_certificate     /etc/ssl/uacme/%s/cert.pem;
     ssl_certificate_key /etc/ssl/uacme/private/%s/key.pem;

     # http3
     ssl_early_data on;

     location / {
       # required for browsers to direct them to quic port
       add_header Alt-Svc 'h3=":443"; ma=86400';
       proxy_set_header Host $host;
       proxy_pass http://%s_backend/;
     }
   }`
   (slug server-name)
   (upstream-server-block upstream-servers)
   server-name server-name server-name
   (slug server-name)))

(defn- server-filename [name] (string "/etc/nginx/conf.d/" name ".conf"))

(defn- ssl-setup []
  (if (util/debug)
    ($? uacme --yes --staging new)
    ($? uacme --yes new)))

(def- self-signed-cert
  `-----BEGIN CERTIFICATE-----
  MIIDsTCCApmgAwIBAgIUZLNUOHW3doGPS38BOpO7UAa0QNUwDQYJKoZIhvcNAQEL
  BQAwaDELMAkGA1UEBhMCVVMxEDAOBgNVBAgMB01vbnRhbmExEjAQBgNVBAcMCUth
  bGlzcGVsbDEQMA4GA1UECgwHUGhvZW5peDEhMB8GA1UEAwwYcGhvZW5peC5qb3Jk
  YW5zY2hhdHouY29tMB4XDTI1MDMwNDE2NTczN1oXDTM1MDMwMjE2NTczN1owaDEL
  MAkGA1UEBhMCVVMxEDAOBgNVBAgMB01vbnRhbmExEjAQBgNVBAcMCUthbGlzcGVs
  bDEQMA4GA1UECgwHUGhvZW5peDEhMB8GA1UEAwwYcGhvZW5peC5qb3JkYW5zY2hh
  dHouY29tMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAtT/JFXdJ71sf
  yZa7KuXKeXPRBzInTdm9AzMovXPGUPwTcQt36oZN4TwgxTL4KDAyOP1Nn7BdnaHd
  DJUXKk0CkKltIzXWPKWHx5oqsL9azZ+E3c0PLOlHEkfccn1GZMGdDaiZAUjnS1s4
  ue+2UF+26QMTfR6C2viMxgcft1ws8xua1ZU5gID37NOlo0s+MQPqHEkQNmJtCwf+
  6VJlu6+/fvlgkrDTjdPEv7JJUO8xG2TWyQ8j8aDRAvv0ATu3ayV7ehDYbYIPAXhw
  pKBf4+0hKLK6E/uCAAqqwJ0JjOAAaP980IO/QOMjTOJZKdPXl+V0NQaH7wgGOBwl
  tty+3zIIeQIDAQABo1MwUTAdBgNVHQ4EFgQUXZU218WanWKYxKDRVC9Ac/LjeYcw
  HwYDVR0jBBgwFoAUXZU218WanWKYxKDRVC9Ac/LjeYcwDwYDVR0TAQH/BAUwAwEB
  /zANBgkqhkiG9w0BAQsFAAOCAQEAeKbmZDQ1dF+9/YKpOLmOG9/5GDVDftOEoZMT
  5f108vVRnkOMylto9P0h50zK/+K45mN7Q+rJMgTFPqgpm28SZE5WqSrRh1ZCyprF
  vcca6oDwzX/8n0B83f2tLMM8/QSkFS/UV1Yueft5LzvTmvk33uDWLBT64dYvgNej
  JjZatZrCBkYe+kx6o00WM2/XK9hiF9uijXN2Uq2fuyrzrIvAk9mmJGgDzZXTZn8v
  HYKrEqW6VWwSwDx9QCnGWF3uss5E42Zk2v5CRQVM09GLm48cba84HWayL6lQimCr
  p5VeLr1Rf4QoML8I0acVP8qzb9xfc0X00gGCvP31WCDmDiwG8A==
  -----END CERTIFICATE-----
  `)

(def- self-signing-key
  `-----BEGIN PRIVATE KEY-----
  MIIEvAIBADANBgkqhkiG9w0BAQEFAASCBKYwggSiAgEAAoIBAQC1P8kVd0nvWx/J
  lrsq5cp5c9EHMidN2b0DMyi9c8ZQ/BNxC3fqhk3hPCDFMvgoMDI4/U2fsF2dod0M
  lRcqTQKQqW0jNdY8pYfHmiqwv1rNn4TdzQ8s6UcSR9xyfUZkwZ0NqJkBSOdLWzi5
  77ZQX7bpAxN9HoLa+IzGBx+3XCzzG5rVlTmAgPfs06WjSz4xA+ocSRA2Ym0LB/7p
  UmW7r79++WCSsNON08S/sklQ7zEbZNbJDyPxoNEC+/QBO7drJXt6ENhtgg8BeHCk
  oF/j7SEosroT+4IACqrAnQmM4ABo/3zQg79A4yNM4lkp09eX5XQ1BofvCAY4HCW2
  3L7fMgh5AgMBAAECggEABXIKJ5Py67cQKG1X6D0JLUb2g8HU/njJPfxef/qnfa1l
  JCNVEf3A/0BgN6yFWifAiofJuj+BQIgpbQRZstKnfhMpDULD0gSjJLMUD0VghAcD
  5eoQR6gmk30HOYVcBRDwGAX1ut0m3dO6y5NRJe8KPsvx3PN6uPt4t0ZlhIvHafJg
  ZBxEwqnjDlasOsDpEH8abfvZP9QiRvR2YjUQNYBK1rDAYNG8nQfhgceh345791/5
  mpNj9Zki9t7R24bKMA7jLp8H+mlYV82BcNDFk/rywhC1c7ND8VMSKRHKUDXOU+I5
  o60hhDHvSBCtvl2Ga8rF22RKFWj+NcFSP7vFnqkzkQKBgQDorCFnMj4si7uEo/zm
  lYTNgXqne4wFGvt+pCDTfQG7a3ePQD8mwIAsw7p0PkqO7TxLVJjCXZ7qTxXQHYMW
  qTFbKRoHXF0oWPQb4d/YzUqmF9rGi05+XWtIQPvrIs/5dMUKgukHV6nd48sFWI4j
  cqXsb+07TzKX11s0SBkbDugKdQKBgQDHa83wWRkYlDm6nq+/ToF2LIRmbngATdLc
  O+eJ2bkF5g4YXb2MMs3ePJFLn0XqGNfwJSdkcKF8nAEWtoWRshT9JWGce7bwpnTT
  37fD98Cto9SA7/HWtAr5bZBMDLI3XCsqrXSZUKg9/+n6Gep19Py/hmmWQIXH/b42
  VWiVU14ddQKBgAy8Fxvx2QtRHpNU8mugdWNWGeN+1JwW7PryesV4ixa5/BJAHvS9
  Bobss5DXM/d8rpck6zOAMkl6yKPaaalc21G0/zK18Hdb3wiDpV/VZKeQmK3TRBmQ
  fWW4ANHO1vk9VeeMYLrBJo/5fswtG6J/DOvS+HYNkKRU6i4DYDRl7XddAoGAfwi5
  g2X+ip3BuJPluKQ17CWnoei1INxyekDe2f2L06odSIBOgsTKR8ulctrfGqUAycWh
  NmZZOJvYRbO3mnwqyqfJanmUq/Adc+qLkZZ9cx9t+0TedbrzUrjstsVPsdxQ0zrz
  j8bFpdkkH2Hq7YFGkGr7T++CSUfmp434tUcKKRECgYAREiWcnPdboolxqoouWtcO
  6ZxatPwxIfIwTjTJe7bvDXoKDwhUbf8T9P+L1qXqY1XDAJsQCc7rZnzH0zIJlviS
  t+PPaHMu2apM+p/URTEh73sOmhrlT8PBL8yavTiaR7m9r3DJVkaHh5ciTfRwkIcP
  ykVCYhkyHAl2cLPn6BEhEA==
  -----END PRIVATE KEY-----
  `)

(defn- insure-path [name]
  ($ mkdir -p ,(string/format "/etc/ssl/uacme/%s" name))
  ($ mkdir -p ,(string/format "/etc/ssl/uacme/private/%s" name)))

(defn- cert-path [name] (string/format "/etc/ssl/uacme/%s/cert.pem" name))
(defn- key-path [name] (string/format "/etc/ssl/uacme/private/%s/key.pem" name))

(defn- setup-self-signed-cert [name]
  (insure-path name)
  (spit (cert-path name) self-signed-cert)
  (spit (key-path name) self-signing-key))

(defn- cert-exists? [name]
  (and (os/stat (cert-path name))
       (os/stat (key-path name))))


######################################################################
#                           Public API
#

(defn restart []
  (util/log "Restarting nginx proxy")
  ($ service nginx restart))

(defn setup-cert [name]
  (when (cert-exists? name) (break))
  (setup-self-signed-cert name)
  (ev/spawn
   (let [cmd (if (util/debug)
               ["uacme" "--staging" "issue" name "-h" "/usr/share/uacme/uacme.sh"]
               ["uacme" "issue" name "-h" "/usr/share/uacme/uacme.sh"])]
     (try (do (os/execute cmd :pex {"UACME_CHALLENGE_PATH" "/srv/acme"})
              (restart))
          ([err fib]
           (print "Obtaining a cert via Acme failed")
           (pp err))))))

(defn init []
  (util/log "Initializing Proxy")
  ($ apk add nginx@nginx)
  ($ mkdir -p /srv/acme/.well-known/acme-challenge)
  ($ mkdir -p /etc/nginx/conf.d/)
  (spit "/etc/nginx/nginx.conf" nginx-conf)
  (spit "/etc/nginx/conf.d/default.conf" default-server)
  (restart)
  (ssl-setup))

(defn cleanup []
  (util/log "Proxy cleanup")
  ($ apk del nginx)
  ($? rm -r /srv/acme/)
  ($? rc-service nginx stop)
  ($? rm -r /etc/nginx/conf.d))

(defn service-up [server-name]
  (util/log "proxy service-up")
  (let [svcs (model/get-by-proxyname server-name)]
    (setup-cert server-name)
    (pp "Past setting up cert")
    (spit (server-filename server-name)
          (service-template server-name svcs))
    (restart)))

(defn service-down [server-name]
  (util/log "proxy service-down")
  ($? rm ,(server-filename server-name))
  (restart))

(defn if-up-down [spec-name]
  (util/log "proxy if-up-down")
  (let [{:proxyname proxyname} (model/get-service-by-name spec-name)]
    (when proxyname (service-down proxyname))))
