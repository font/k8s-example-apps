#!/usr/bin/env bash

docker run -v ~/pacman-canvas:/var/www/html --name pacman-nginx-mongo-0 -p 8000:80 -p 27017:27017 -d font/pacman-nginx-app:dev
docker run -v ~/pacman-canvas:/var/www/html --name pacman-nginx-mongo-1 -p 8001:80 -p 27018:27017 -d font/pacman-nginx-app:dev
docker run -v ~/pacman-canvas:/var/www/html --name pacman-nginx-mongo-2 -p 8002:80 -p 27019:27017 -d font/pacman-nginx-app:dev
