FROM ubuntu:16.04

MAINTAINER Ivan Font <ifont@redhat.com>

# 1. Update and install packages
RUN apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 0C49F3730359A14518585931BC711F9BA15703C6
RUN echo "deb [ arch=amd64,arm64 ] http://repo.mongodb.org/apt/ubuntu xenial/mongodb-org/3.4 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-3.4.list
# This should automatically add the mongodb.so extension to .ini files
RUN apt-get -y update && \
    apt-get -y install nginx php-fpm php-mongodb composer mongodb-org curl

# 2. Run composer require for mongodb in the directory right above nginx root directory
WORKDIR /var/www
RUN composer require mongodb/mongodb --ignore-platform-reqs

# 3. Set nginx configuration
RUN echo 'server {' > /etc/nginx/sites-available/default && \
    echo 'listen 80 default_server;' >> /etc/nginx/sites-available/default && \
    echo 'listen [::]:80 default_server;' >> /etc/nginx/sites-available/default && \
    echo 'root /var/www/html;' >> /etc/nginx/sites-available/default && \
    echo 'index index.php index.html index.htm index.nginx-debian.html;' >> /etc/nginx/sites-available/default && \
    echo 'server_name _;' >> /etc/nginx/sites-available/default && \
    echo 'location / {' >> /etc/nginx/sites-available/default && \
    echo '    try_files $uri $uri/ =404;' >> /etc/nginx/sites-available/default && \
    echo '}' >> /etc/nginx/sites-available/default && \
    echo 'location ~ \.php$ {' >> /etc/nginx/sites-available/default && \
    echo '    include snippets/fastcgi-php.conf;' >> /etc/nginx/sites-available/default && \
    echo '    fastcgi_pass unix:/run/php/php7.0-fpm.sock;' >> /etc/nginx/sites-available/default && \
    echo '}' >> /etc/nginx/sites-available/default && \
    echo 'location ~ /\.ht {' >> /etc/nginx/sites-available/default && \
    echo '    deny all;' >> /etc/nginx/sites-available/default && \
    echo '}' >> /etc/nginx/sites-available/default && \
    echo '}' >> /etc/nginx/sites-available/default

# 4. Go into nginx root directory and pull pacman game
WORKDIR /var/www/html
RUN rm -rf *

# 5. Add mongod data directory and specify volume that will be bind mounted at runtime
RUN mkdir -p /data/db
VOLUME ["/var/www/html"]

# 6. expose nginx port
EXPOSE 80

# 7. expose mongo port
EXPOSE 27017

# 7. Run nginx and php-fpm along with some forever command e.g. while loop
CMD service nginx start && service php7.0-fpm start && /usr/bin/mongod --replSet rs0
