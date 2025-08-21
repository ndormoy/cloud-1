#!/usr/bin/env bash
set -euo pipefail

log() { echo "[$(date -Is)] $*"; }

if ! command -v dnf >/dev/null 2>&1; then
  log "This script expects Amazon Linux 2023 (dnf). Aborting."
  exit 1
fi

log "Updating system and installing base packages"
sudo dnf update -y
sudo dnf install -y --allowerasing docker amazon-efs-utils jq curl awscli

log "Installing Docker Compose manually"
sudo mkdir -p /usr/local/lib/docker/cli-plugins
sudo curl -SL https://github.com/docker/compose/releases/download/v2.27.0/docker-compose-linux-x86_64 -o /usr/local/lib/docker/cli-plugins/docker-compose
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

log "Enabling and starting Docker"
sudo systemctl enable --now docker
sudo usermod -aG docker ec2-user || true

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
export WP_ADMIN_PASSWORD_SECRET_ARN="${wp_admin_password_secret_arn}"
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

echo "DB_PASSWORD_SECRET_ARN"
echo "$${DB_PASSWORD_SECRET_ARN}"

fetch_db_password() {
  if [[ -n "$${DB_PASSWORD_SECRET_ARN}" ]]; then
    aws secretsmanager get-secret-value --secret-id "$${DB_PASSWORD_SECRET_ARN}" \
      --query 'SecretString' --output text | jq -r '.password // .db_password // .PASSWORD // empty'
  else
    echo "Error feching db password"
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

fetch_wp_admin_password() {
  if [[ -n "$${WP_ADMIN_PASSWORD_SECRET_ARN}" ]]; then
    aws secretsmanager get-secret-value --secret-id "$${WP_ADMIN_PASSWORD_SECRET_ARN}" \
      --query 'SecretString' --output text
  else
    echo "Error feching wp admin password"
  fi
}

log "Fetching DB password and WP salts"
DB_PASSWORD="$(fetch_db_password)"
DB_PASSWORD_ESCAPED=$(printf '%s\n' "$${DB_PASSWORD}" | sed 's/\$/$$/g')
WP_SALTS="$(fetch_wp_salts)"
WP_ADMIN_PASSWORD="$(fetch_wp_admin_password)"

if [[ -z "$${DB_PASSWORD:-}" ]]; then
  log "ERROR: DB password not resolved (secret empty?). Aborting."
  exit 1
fi

if [[ -z "$${WP_SALTS:-}" ]]; then
  log "ERROR: WP salts not resolved from SSM. Aborting."
  exit 1
fi

if [[ -z "$${WP_ADMIN_PASSWORD:-}" ]]; then
  log "ERROR: WP admin password not resolved (secret empty?). Aborting."
  exit 1
fi

FRESH_MOUNT=false

log "Setting up EFS mount $${EFS_FS_ID}"
sudo mkdir -p /mnt/efs
if ! mountpoint -q /mnt/efs; then
  log "Mounting EFS filesystem: $${EFS_FS_ID} [...]"
  while true; do
    if sudo mount -t efs -o tls "$${EFS_FS_ID}":/ /mnt/efs; then
      log "EFS mounted successfully"
      FRESH_MOUNT=true
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

log "EFS Mounted"

if [[ "$${FRESH_MOUNT}" == "true" ]] || [[ ! -f /mnt/efs/wp-config.php ]]; then
  log "Setting WordPress permissions on EFS (fresh mount or empty EFS)"
  sudo chown -R 33:33 /mnt/efs 2>/dev/null || true
  sudo chmod -R 777 /mnt/efs 2>/dev/null || true
else
  log "EFS already mounted with WordPress files, skipping permissions"
fi

log "Preparing WordPress configuration with salts"
sudo mkdir -p /opt/wordpress

cat > /opt/wordpress/wp-config-template.php << EOF
<?php
/**
 * Conf WordPress with perso salts
 */

// Configuration base de données
define('DB_NAME', '$${AURORA_DB_NAME}');
define('DB_USER', '$${AURORA_DB_USER}'); 
define('DB_PASSWORD', '$${DB_PASSWORD}');
define('DB_HOST', '$${AURORA_HOST}');
define('DB_CHARSET', 'utf8mb4');
define('DB_COLLATE', '');

// --- CONFIGURATION W3 TOTAL CACHE for ELASTICACHE ---
define('WP_CACHE', true);
define('W3TC_CACHE_OBJECT_ENGINE', 'memcached');
define('W3TC_CACHE_MEMCACHED_SERVERS', '$${MEMCACHED_HOST}:$${MEMCACHED_PORT}');

// Salts de sécurité depuis AWS SSM
$${WP_SALTS}

// Configuration HTTP/HTTPS
define('WP_HOME', '$${WP_HOME}');
define('WP_SITEURL', '$${WP_SITEURL}');



// Fix pour mixed content en HTTP
define('FORCE_SSL_ADMIN', false);
\$_SERVER['HTTPS'] = 'off';


if (isset(\$_SERVER['HTTP_X_FORWARDED_PROTO']) && \$_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
    \$_SERVER['HTTPS'] = 'on';
}
\$_SERVER['HTTP_HOST'] = parse_url(WP_HOME, PHP_URL_HOST);
\$_SERVER['SERVER_NAME'] = parse_url(WP_HOME, PHP_URL_HOST);

// Désactiver les mises à jour automatiques en production
define('WP_AUTO_UPDATE_CORE', false);
define('DISALLOW_FILE_EDIT', true);

// Configuration des révisions
define('WP_POST_REVISIONS', 3);

// Configuration debug (à désactiver en production)
define('WP_DEBUG', false);
define('WP_DEBUG_LOG', false);
define('WP_DEBUG_DISPLAY', false);

// Configuration mémoire
define('WP_MEMORY_LIMIT', '256M');

// Table prefix
\$table_prefix = 'wp_';

if (!defined('ABSPATH')) {
    define('ABSPATH', __DIR__ . '/');
}

require_once ABSPATH . 'wp-settings.php';
EOF

sudo mkdir -p /opt/wordpress/nginx
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

sudo cp /opt/wordpress/.env /mnt/efs/.env

log "Preparing application directory and starting containers"

cat > docker-compose.yaml <<'EOF'
${docker_compose_content}
EOF
cat > nginx/default.conf <<'EOF'
${nginx_conf_content}
EOF


log "Starting containers (docker compose [...])"
sudo /usr/bin/docker compose --env-file ./.env up -d

while true; do
  if curl -fsS http://127.0.0.1/server-id >/dev/null; then break; fi
  sleep 2
done

log "Setting up WordPress configuration file"
if [[ ! -f /mnt/efs/wp-config.php ]]; then
  log "Copying custom wp-config to EFS (first time)"
  
  while true; do
    if [[ -f /mnt/efs/wp-settings.php ]]; then
      log "WordPress core files detected, copying wp-config"
      break
    fi
    log "Waiting for WordPress auto-download..."
    sleep 2
  done

  if [[ -f /mnt/efs/wp-settings.php ]]; then
    sudo cp /opt/wordpress/wp-config-template.php /mnt/efs/wp-config.php
    sudo chown 33:33 /mnt/efs/wp-config.php
    sudo chmod 644 /mnt/efs/wp-config.php
    log "Custom wp-config.php installed successfully"
  else
    log "ERROR: WordPress core not found, cannot install wp-config"
    exit 1
  fi
else
  log "wp-config.php already exists on EFS, skipping copy"
fi

log "Checking WordPress installation status..."

INSTALL_LOCK="/mnt/efs/.wp-install-lock"

is_wordpress_installed() {
    if sudo docker exec wp-cli bash -lc "wp core is-installed --allow-root" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

if [[ -f "$${INSTALL_LOCK}" ]]; then
    log "WordPress installation in progress by another instance, waiting..."
    while true; do
        if [[ ! -f "$${INSTALL_LOCK}" ]] || is_wordpress_installed; then
            log "Installation completed by another instance"
            break
        fi
        sleep 5
    done
else
    if ! is_wordpress_installed; then
        log "WordPress not installed, this instance will handle installation"
        
        touch "$${INSTALL_LOCK}"
        
        log "Waiting for DB to be ready..."
        while true; do
          if sudo docker exec wp-cli bash -lc "export \$(grep -v '^#' /var/www/html/.env | xargs) && wp db check --allow-root"; then
            log "WordPress database connection is OK."
            break
          fi
          log "Waiting for DB connection..."
          sleep 2
        done

        log "Running WordPress Core Install via wp-cli"
        sudo docker exec wp-cli bash -lc "
          wp core install \
            --url='$${WP_HOME}' \
            --title='Mon Site Cloud TOTO' \
            --admin_user='${wp_admin_user}' \
            --admin_password='$${WP_ADMIN_PASSWORD}' \
            --admin_email='${wp_admin_email}' \
            --allow-root" || {
            log "WordPress installation failed, removing lock"
            rm -f "$${INSTALL_LOCK}"
            exit 1
        }

        log "Setting up WordPress directories and permissions"
        sudo mkdir -p /mnt/efs/wp-content/uploads
        sudo mkdir -p /mnt/efs/wp-content/upgrade
        sudo mkdir -p /mnt/efs/wp-content/plugins/server-info-display
        sudo chown -R 33:33 /mnt/efs/wp-content
        sudo chmod -R 755 /mnt/efs/wp-content
        sudo chmod -R 777 /mnt/efs/wp-content/upgrade

        log "Waiting for WordPress installation to be fully complete..."
        while true; do
            if sudo docker exec wp-cli bash -lc "export \$(grep -v '^#' /var/www/html/.env | xargs) && wp core is-installed --allow-root"; then
                log "WordPress core is successfully installed."
                break
            fi
            log "Waiting for core installation to finalize..."
            sleep 3
        done

        log "Installing and activating W3 Total Cache"
        
        sudo docker exec --user www-data wp-cli bash -lc "export \$(grep -v '^#' /var/www/html/.env | xargs); \
          wp plugin install w3-total-cache --activate --url=$${WP_HOME} --path=/var/www/html";
        log "W3 Total Cache installed and activated"

        log "Creating and activating server ID display plugin"
        sudo mkdir -p /mnt/efs/wp-content/mu-plugins/
        sudo tee /mnt/efs/wp-content/mu-plugins/server-info-display.php > /dev/null <<'PLUGIN_EOF'
        <?php
        /**
        * Plugin Name: Server Info Display
        * Description: Adds the server hostname to the footer.
        */
        function display_server_info_in_footer() {
            $server_id = getenv('SERVER_ID') ?: gethostname();
            echo '<div style="position:fixed;bottom:10px;right:10px;background:#333;color:#fff;padding:8px 12px;border-radius:5px;font-size:11px;z-index:9999;font-family:monospace;">Served by: ' . esc_html($server_id) . '</div>';
        }
        add_action('wp_footer', 'display_server_info_in_footer');
PLUGIN_EOF

        sudo chown -R 33:33 /mnt/efs/wp-content/mu-plugins/

        rm -f "$${INSTALL_LOCK}"

    else
        log "WordPress already installed, skipping installation"
    fi
fi

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

log "Bootstrap complete"
