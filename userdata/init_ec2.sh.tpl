#!/usr/bin/env bash
set -euo pipefail

log() { echo "[$(date -Is)] $*"; }

# ---------- 0) Préchecks OS / Réseaux ----------
if ! command -v dnf >/dev/null 2>&1; then
  log "This script expects Amazon Linux 2023 (dnf). Aborting."
  exit 1
fi

# ---------- 1) Mises à jour & packages ----------
log "Updating system and installing packages"
sudo dnf update -y
sudo dnf install -y docker docker-compose-plugin amazon-efs-utils jq unzip curl awscli

# ---------- 2) Docker ----------
log "Enabling and starting Docker"
sudo systemctl enable --now docker
sudo usermod -aG docker ec2-user || true

# ---------- 3) Variables ----------
export EFS_FS_ID="${efs_fs_id:-}"
export AURORA_HOST="${aurora_writer_endpoint:-}"
export AURORA_DB_NAME="${aurora_db_name:-wordpressdb}"
export AURORA_DB_USER="${aurora_db_user:-admin}"
export DB_PASSWORD_SECRET_ARN="${db_password_secret_arn:-}"
export WP_SALTS_PARAM_NAME="${wp_salts_param_name:-}"
export MEMCACHED_HOST="${memcached_host:-}"
export MEMCACHED_PORT="${memcached_port:-11211}"
export WP_HOME="${wp_home:-https://example.cloudfront.net}"
export WP_SITEURL="${wp_siteurl:-https://example.cloudfront.net}"
# export SERVER_ID="$(hostname -f)"
export SERVER_ID=""

SERVER_ID="$(hostname -f)"

# Validation basique des variables essentielles
missing=0
for v in EFS_FS_ID AURORA_HOST AURORA_DB_NAME AURORA_DB_USER MEMCACHED_HOST; do
  if [[ -z "${!v:-}" ]]; then
    log "ERROR: variable $v is empty"
    missing=1
  fi
done
if [[ "$missing" -eq 1 ]]; then
  log "Some required variables are missing. Aborting."
  exit 1
fi

# ---------- 4) Secrets ----------
fetch_db_password() {
  if [[ -n "${DB_PASSWORD_SECRET_ARN}" ]]; then
    aws secretsmanager get-secret-value --secret-id "$DB_PASSWORD_SECRET_ARN" \
      --query 'SecretString' --output text | jq -r '.password // .db_password // .PASSWORD // empty'
  else
    echo "${aurora_db_password:-}"
  fi
}

fetch_wp_salts() {
  if [[ -n "${WP_SALTS_PARAM_NAME}" ]]; then
    aws ssm get-parameter --name "$WP_SALTS_PARAM_NAME" --with-decryption \
      --query 'Parameter.Value' --output text
  else
    curl -fsSL https://api.wordpress.org/secret-key/1.1/salt/
  fi
}

log "Fetching DB password and WP salts if configured"
DB_PASSWORD="$(fetch_db_password || true)"
WP_SALTS="$(fetch_wp_salts || true)"

if [[ -z "${DB_PASSWORD:-}" ]]; then
  log "ERROR: DB password not resolved (secret empty?). Aborting."
  exit 1
fi
if [[ -z "${WP_SALTS:-}" ]]; then
  log "WARN: WP salts empty; generating unique salts breaks SSO across instances."
  WP_SALTS="$(curl -fsSL https://api.wordpress.org/secret-key/1.1/salt/)"
fi

# ---------- 5) Monter EFS ----------
log "Mounting EFS $EFS_FS_ID"
sudo mkdir -p /mnt/efs
if ! mountpoint -q /mnt/efs; then
  # retry loop in case mount targets not fully ready at first boot
  for i in {1..10}; do
    if sudo mount -t efs -o tls "${EFS_FS_ID}":/ /mnt/efs; then
      break
    fi
    log "EFS mount failed, retrying in 6s..."
    sleep 6
  done
fi
if ! mountpoint -q /mnt/efs; then
  log "ERROR: EFS not mounted. Aborting."
  exit 1
fi

if ! grep -q "${EFS_FS_ID}:/ /mnt/efs efs" /etc/fstab; then
  echo "${EFS_FS_ID}:/ /mnt/efs efs _netdev,tls 0 0" | sudo tee -a /etc/fstab
fi

# ---------- 6) Préparer wp-content ----------
sudo mkdir -p /mnt/efs/wp-content
sudo chown -R 33:33 /mnt/efs/wp-content
sudo chmod -R 775 /mnt/efs/wp-content || true

# ---------- 7) Dossier app ----------
sudo mkdir -p /opt/wordpress
cd /opt/wordpress

cat > .env <<EOF
SERVER_ID=${SERVER_ID}
WP_HOME=${WP_HOME}
WP_SITEURL=${WP_SITEURL}

DB_HOST=${AURORA_HOST}
DB_NAME=${AURORA_DB_NAME}
DB_USER=${AURORA_DB_USER}
DB_PASSWORD=${DB_PASSWORD}

MEMCACHED_HOST=${MEMCACHED_HOST}
MEMCACHED_PORT=${MEMCACHED_PORT}
EOF

echo "${WP_SALTS}" > wp-salts.txt

# ---------- 8) docker-compose ----------
cat > docker-compose.yml <<'YML'
services:
  wordpress:
    image: wordpress:php8.2-fpm
    container_name: wp-php
    environment:
      WORDPRESS_DB_HOST: ${DB_HOST}
      WORDPRESS_DB_NAME: ${DB_NAME}
      WORDPRESS_DB_USER: ${DB_USER}
      WORDPRESS_DB_PASSWORD: ${DB_PASSWORD}
      WP_HOME: ${WP_HOME}
      WP_SITEURL: ${WP_SITEURL}
      MEMCACHED_HOST: ${MEMCACHED_HOST}
      MEMCACHED_PORT: ${MEMCACHED_PORT}
    volumes:
      - /mnt/efs/wp-content:/var/www/html/wp-content
      - ./wp-salts.txt:/docker-entrypoint-initwp.d/wp-salts.txt:ro
      - ./wp-init:/docker-entrypoint-initwp.d
    restart: unless-stopped

  nginx:
    image: nginx:stable
    container_name: wp-nginx
    ports:
      - "80:80"
    depends_on:
      - wordpress
    volumes:
      - /mnt/efs/wp-content:/var/www/html/wp-content:ro
      - ./nginx/default.conf:/etc/nginx/conf.d/default.conf:ro
    restart: unless-stopped

  phpmyadmin:
    image: phpmyadmin:latest
    container_name: phpmyadmin
    environment:
      PMA_HOST: ${DB_HOST}
      PMA_USER: ${DB_USER}
      PMA_PASSWORD: ${DB_PASSWORD}
    depends_on:
      - wordpress
    restart: unless-stopped

  wpcli:
    image: wordpress:cli-php8.2
    container_name: wp-cli
    depends_on:
      - wordpress
    volumes:
      - /mnt/efs/wp-content:/var/www/html/wp-content
      - ./wp-salts.txt:/docker-entrypoint-initwp.d/wp-salts.txt:ro
      - ./wp-init:/docker-entrypoint-initwp.d
    working_dir: /var/www/html
    entrypoint: ["bash","-lc","sleep infinity"]
YML

mkdir -p nginx
cat > nginx/default.conf <<'NGINX'
server {
  listen 80;
  server_name _;

  location /server-id {
    default_type text/plain;
    return 200 "$hostname\n";
  }

  root /var/www/html;
  index index.php index.html;

  location / {
    try_files $uri /index.php?$args;
  }

  location ~ \.php$ {
    include fastcgi_params;
    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    fastcgi_pass wordpress:9000;
  }

  location /phpmyadmin/ {
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_pass http://phpmyadmin:80/;
  }

  location ~* \.(css|js|jpg|jpeg|png|gif|ico|svg|woff2?)$ {
    expires 7d;
    access_log off;
    add_header Cache-Control "public";
    try_files $uri =404;
  }
}
NGINX

mkdir -p wp-init
cat > wp-init/10-wp-config.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

WP_CONFIG="/var/www/html/wp-config.php"

# attendre wp-config si nécessaire
for i in {1..30}; do
  [[ -f "$WP_CONFIG" ]] && break
  sleep 2
done

# injecter SALTS si manquants
if ! grep -q "AUTH_KEY" "$WP_CONFIG" && [[ -f "/docker-entrypoint-initwp.d/wp-salts.txt" ]]; then
  cat /docker-entrypoint-initwp.d/wp-salts.txt >> "$WP_CONFIG"
fi

# forcer URLs
if ! grep -q "WP_HOME" "$WP_CONFIG"; then
  echo "define('WP_HOME', getenv('WP_HOME')); define('WP_SITEURL', getenv('WP_SITEURL'));" >> "$WP_CONFIG"
fi

# config Memcached
if ! grep -q "MEMCACHED_SERVERS" "$WP_CONFIG"; then
  echo "\$memcached_servers = array( array(getenv('MEMCACHED_HOST'), intval(getenv('MEMCACHED_PORT'))) );" >> "$WP_CONFIG"
fi
EOF
chmod +x wp-init/10-wp-config.sh

# ---------- 9) Démarrage ----------
log "Starting containers"
sudo /usr/bin/docker compose --env-file ./.env up -d

for i in {1..60}; do
  if curl -fsS http://127.0.0.1/server-id >/dev/null; then break; fi
  sleep 2
done

# ---------- 10) Healthcheck + Activation plugin Memcached via wp-cli ----------
log "Waiting for WordPress to be ready"
for i in {1..60}; do
  if sudo docker exec wp-php sh -c 'php -v >/dev/null 2>&1'; then
    break
  fi
  sleep 2
done

# Installer W3 Total Cache comme solution d'object cache (compatible Memcached)
log "Installing and activating W3 Total Cache"
sudo docker exec wp-cli bash -lc 'wp plugin install w3-total-cache --activate --allow-root || true'

# ---------- 11) systemd ----------
log "Installing systemd unit for compose"
sudo bash -c 'cat > /etc/systemd/system/wordpress-stack.service <<SYS
[Unit]
Description=WordPress stack (nginx + php-fpm) via docker compose
Requires=docker.service network-online.target
After=docker.service network-online.target

[Service]
Type=oneshot
WorkingDirectory=/opt/wordpress
RemainAfterExit=yes
ExecStart=/usr/bin/docker compose --env-file ./.env up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
SYS'

sudo systemctl daemon-reload
sudo systemctl enable --now wordpress-stack.service

# ---------- 12) Logging minimal ----------
log "Bootstrap complete"
