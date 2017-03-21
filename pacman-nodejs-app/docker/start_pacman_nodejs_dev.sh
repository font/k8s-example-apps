#!/usr/bin/env bash

# NodeJS
docker run -v ~/pacman:/usr/src/app --name pacman-nodejs-0 -p 8080:8080 -d font/pacman-nodejs-app:nodejs_dev
docker run -v ~/pacman:/usr/src/app --name pacman-nodejs-1 -p 8081:8080 -d font/pacman-nodejs-app:nodejs_dev
docker run -v ~/pacman:/usr/src/app --name pacman-nodejs-2 -p 8082:8080 -d font/pacman-nodejs-app:nodejs_dev
