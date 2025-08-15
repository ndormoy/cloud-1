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
      - /mnt/efs:/var/www/html
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
      - /mnt/efs:/var/www/html:ro
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
    environment:
      WORDPRESS_DB_HOST: ${DB_HOST}
      WORDPRESS_DB_NAME: ${DB_NAME}
      WORDPRESS_DB_USER: ${DB_USER}
      WORDPRESS_DB_PASSWORD: ${DB_PASSWORD}
    volumes:
      - /mnt/efs:/var/www/html
      - ./wp-salts.txt:/docker-entrypoint-initwp.d/wp-salts.txt:ro
      - ./wp-init:/docker-entrypoint-initwp.d
    working_dir: /var/www/html
    entrypoint: ["bash","-lc","sleep infinity"]
