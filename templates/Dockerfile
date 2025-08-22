FROM wordpress:php8.2-fpm AS wp-fpm

# Install PHP memcached extension and dependencies
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        libmemcached-dev \
        libsasl2-dev \
        zlib1g-dev \
        libzip-dev \
        pkg-config \
        unzip; \
    docker-php-ext-install zip; \
    pecl install memcached; \
    docker-php-ext-enable memcached; \
    rm -rf /var/lib/apt/lists/*
