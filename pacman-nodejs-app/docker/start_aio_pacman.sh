#!/usr/bin/env bash

docker run -v ~/pacman:/var/www/html --name pacman-nodejs-mongo-0 -p 8000:80 -p 27017:27017 -d font/pacman-nodejs-app:dev
docker run -v ~/pacman:/var/www/html --name pacman-nodejs-mongo-1 -p 8001:80 -p 27018:27017 -d font/pacman-nodejs-app:dev
docker run -v ~/pacman:/var/www/html --name pacman-nodejs-mongo-2 -p 8002:80 -p 27019:27017 -d font/pacman-nodejs-app:dev
