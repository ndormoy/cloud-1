# FROM wordpress:php8.2-fpm AS wp-fpm

# RUN set -eux; \
#     apt-get update; \
#     apt-get install -y --no-install-recommends \
#         libmemcached-dev \
#         libsasl2-dev \
#         zlib1g-dev \
#         libzip-dev \
#         pkg-config \
#         unzip; \
#     docker-php-ext-install zip; \
#     pecl install memcached; \
#     docker-php-ext-enable memcached; \
#     rm -rf /var/lib/apt/lists/*

# FROM wordpress:cli-php8.2 AS wp-cli

# RUN set -eux; \
#     apt-get update; \
#     apt-get install -y --no-install-recommends \
#         less \
#         default-mysql-client \
#         libmemcached-dev \
#         libsasl2-dev \
#         zlib1g-dev \
#         libzip-dev \
#         pkg-config \
#         unzip; \
#     pecl install memcached; \
#     docker-php-ext-enable memcached; \
#     rm -rf /var/lib/apt/lists/*
