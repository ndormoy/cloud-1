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
