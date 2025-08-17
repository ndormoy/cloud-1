server {
  listen 80;
  server_name _;

  add_header Content-Security-Policy "upgrade-insecure-requests;" always;
  add_header X-Content-Type-Options "nosniff" always;
  add_header X-Frame-Options "SAMEORIGIN" always;

  location /server-id {
    default_type text/plain;
    add_header Cache-Control "no-cache, no-store, must-revalidate";
    add_header Pragma "no-cache"; 
    add_header Expires "0";
    return 200 "$hostname\n";
  }

  location /server-info {
    default_type application/json;
    add_header Cache-Control "no-cache";
    return 200 '{"server":"$hostname","timestamp":"$time_iso8601"}';
  }

  root /var/www/html;
  index index.php index.html;

  location / {
    try_files $uri $uri/ /index.php?$args;
    
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto http;
    proxy_set_header Host $host;
  }

  location ~ \.php$ {
    include fastcgi_params;
    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    fastcgi_param HTTP_X_FORWARDED_PROTO $http_x_forwarded_proto;
    fastcgi_pass wordpress:9000;
  }

  location /phpmyadmin/ {
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_pass http://phpmyadmin:80/;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_redirect off;
  }

  location ~* \.(css|js|jpg|jpeg|png|gif|ico|svg|woff2?)$ {
    expires 7d;
    access_log off;
    add_header Cache-Control "public";
    try_files $uri =404;
  }
}
