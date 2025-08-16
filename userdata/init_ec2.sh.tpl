#!/usr/bin/env bash
set -euo pipefail

log() { echo "[$(date -Is)] $*"; }

# ---------- 0) Préchecks OS / Réseaux ----------
if ! command -v dnf >/dev/null 2>&1; then
  log "This script expects Amazon Linux 2023 (dnf). Aborting."
  exit 1
fi

# ---------- 1) Mises à jour & packages ----------
log "Updating system and installing base packages"
sudo dnf update -y
sudo dnf install -y --allowerasing docker amazon-efs-utils jq curl awscli

log "Installing Docker Compose manually"
sudo mkdir -p /usr/local/lib/docker/cli-plugins
sudo curl -SL https://github.com/docker/compose/releases/download/v2.27.0/docker-compose-linux-x86_64 -o /usr/local/lib/docker/cli-plugins/docker-compose
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# ---------- 2) Docker ----------
log "Enabling and starting Docker"
sudo systemctl enable --now docker
sudo usermod -aG docker ec2-user || true

# ---------- 3) Variables ----------
export EFS_FS_ID="${efs_fs_id}"
export AURORA_HOST="${aurora_writer_endpoint}"
export AURORA_DB_NAME="${aurora_db_name}"
export AURORA_DB_USER="${aurora_db_user}"
export DB_PASSWORD_SECRET_ARN="${db_password_secret_arn}"
export WP_SALTS_PARAM_NAME="${wp_salts_param_name}"
export MEMCACHED_HOST="${memcached_host}"
export MEMCACHED_PORT="${memcached_port}"
export WP_HOME="${wp_home}"
export WP_SITEURL="${wp_siteurl}"
export SERVER_ID=""

SERVER_ID="$(hostname -f)"

required_vars=(
  EFS_FS_ID
  AURORA_HOST
  AURORA_DB_NAME
  AURORA_DB_USER
  MEMCACHED_HOST
  DB_PASSWORD_SECRET_ARN
  WP_SALTS_PARAM_NAME
  WP_HOME
  WP_SITEURL
)

missing=0
for v in "$${required_vars[@]}"; do
  if [ -z "$${!v:-}" ]; then
    log "ERROR: variable $v is empty"
    missing=1
  fi
done
if [ "$missing" -ne 0 ]; then
  exit 1
fi

# ---------- 4) Secrets ----------

echo "DB_PASSWORD_SECRET_ARN"
echo "$${DB_PASSWORD_SECRET_ARN}"

fetch_db_password() {
  if [[ -n "$${DB_PASSWORD_SECRET_ARN}" ]]; then
    aws secretsmanager get-secret-value --secret-id "$${DB_PASSWORD_SECRET_ARN}" \
      --query 'SecretString' --output text | jq -r '.password // .db_password // .PASSWORD // empty'
  else
    echo "$${aurora_db_password:-}"
  fi
}

fetch_wp_salts() {
  if [[ -z "$${WP_SALTS_PARAM_NAME}" ]]; then
    log "ERROR: WP_SALTS_PARAM_NAME variable is not set. Cannot fetch salts."
    return 1
  fi

  aws ssm get-parameter --name "$${WP_SALTS_PARAM_NAME}" --with-decryption \
    --query 'Parameter.Value' --output text
}

log "Fetching DB password and WP salts"
DB_PASSWORD="$(fetch_db_password)"
DB_PASSWORD_ESCAPED=$(printf '%s\n' "$${DB_PASSWORD}" | sed 's/\$/$$/g')
WP_SALTS="$(fetch_wp_salts)"

if [[ -z "$${DB_PASSWORD:-}" ]]; then
  log "ERROR: DB password not resolved (secret empty?). Aborting."
  exit 1
fi
if [[ -z "$${WP_SALTS:-}" ]]; then
  log "ERROR: WP salts not resolved from SSM. Aborting."
  exit 1
fi


# ---------- 5) Monter EFS ----------
log "Mounting EFS $${EFS_FS_ID}"
sudo mkdir -p /mnt/efs
if ! mountpoint -q /mnt/efs; then
  # retry loop in case mount targets not fully ready at first boot
  for i in {1..10}; do
    if sudo mount -t efs -o tls "$${EFS_FS_ID}":/ /mnt/efs; then
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

if ! grep -q "$${EFS_FS_ID}:/ /mnt/efs efs" /etc/fstab; then
  echo "$${EFS_FS_ID}:/ /mnt/efs efs _netdev,tls 0 0" | sudo tee -a /etc/fstab
fi

# ---------- 6) Préparer wp-content ----------
sudo mkdir -p /mnt/efs/wp-content
sudo chown -R 33:33 /mnt/efs/wp-content
# sudo chmod -R g+w /mnt/efs/wp-content
sudo chmod -R 775 /mnt/efs/wp-content || true

# ---------- 7) Dossier app ----------


sudo mkdir -p /opt/wordpress
cd /opt/wordpress

cat > .env <<EOF
SERVER_ID=$${SERVER_ID}
WP_HOME=$${WP_HOME}
WP_SITEURL=$${WP_SITEURL}

DB_HOST=$${AURORA_HOST}
DB_NAME=$${AURORA_DB_NAME}
DB_USER=$${AURORA_DB_USER}
DB_PASSWORD=$${DB_PASSWORD_ESCAPED}

MEMCACHED_HOST=$${MEMCACHED_HOST}
MEMCACHED_PORT=$${MEMCACHED_PORT}
EOF

# A VOIR
sudo cp /opt/wordpress/.env /mnt/efs/.env

echo "$${WP_SALTS}" > wp-salts.txt

# ---------- 8) a) docker-compose ----------

log "Copy Docker Compose"

cat > docker-compose.yaml <<'EOF'
${docker_compose_content}
EOF

# ---------- 8) b) nginx ----------

log "Copy configuration files (NGINX)"

mkdir -p nginx
cat > nginx/default.conf <<'EOF'
${nginx_conf_content}
EOF


# ---------- 8) c) Wordpress ----------

log "Copy wordpress config"

mkdir -p wp-init
cat > wp-init/10-wp-config.sh <<'EOF'
${wp_init_script_content}
EOF
chmod +x wp-init/10-wp-config.sh

# ---------- 9) Démarrage ----------
log "Starting containers (docker compose [...])"
sudo /usr/bin/docker compose --env-file ./.env up -d

for i in {1..60}; do
  if curl -fsS http://127.0.0.1/server-id >/dev/null; then break; fi
  sleep 2
done

# ---------- 10) Healthcheck + Activation plugin Memcached via wp-cli ----------

# for i in {1..60}; do
#   if sudo docker exec wp-cli bash -lc 'wp db check --allow-root'; then
#     log "WordPress database connection is OK."
#     break
#   fi
#   log "Waiting for DB connection... ($i/60)"
#   sleep 2
# done

# if ! sudo docker exec wp-cli bash -lc 'wp db check --allow-root'; then
#     log "ERROR: WordPress DB connection failed after 2 minutes. Aborting."
#     exit 1
# fi


# log "Waiting for WordPress installation to complete..."
# for i in {1..60}; do
#   if sudo docker exec wp-cli bash -lc 'wp core is-installed --allow-root'; then
#     log "WordPress is fully installed."
#     break
#   fi
#   log "Waiting for WordPress core installation... ($i/60)"
#   sleep 5
# done

# if ! sudo docker exec wp-cli bash -lc 'wp core is-installed --allow-root'; then
#     log "ERROR: WordPress installation failed after timeout. Aborting."
#     exit 1
# fi


# log "Waiting for WordPress installation to complete..."
# for i in {1..60}; do
#   if sudo docker exec wp-cli bash -lc "wp core is-installed --url=$${WP_HOME} --allow-root"; then
#     log "WordPress is fully installed and ready."
#     break
#   fi
#   log "Waiting for WordPress core installation... ($i/60)"
#   sleep 5
# done

# if ! sudo docker exec wp-cli bash -lc "wp core is-installed --url=$${WP_HOME} --allow-root"; then
#     log "ERROR: WordPress installation failed after timeout. Aborting."
#     exit 1
# fi









for i in {1..60}; do
  if sudo docker exec wp-cli bash -lc "export \$(grep -v '^#' /var/www/html/.env | xargs) && wp core is-installed --url=$${WP_HOME} --allow-root"; then
    log "WordPress is fully installed and ready."
    break
  fi
  log "Waiting for WordPress core installation... ($i/60)"
  sleep 5
done

if ! sudo docker exec wp-cli bash -lc "export \$(grep -v '^#' /var/www/html/.env | xargs) && wp core is-installed --url=$${WP_HOME} --allow-root"; then
    log "ERROR: WordPress installation failed after timeout. Aborting."
    exit 1
fi


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
