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
