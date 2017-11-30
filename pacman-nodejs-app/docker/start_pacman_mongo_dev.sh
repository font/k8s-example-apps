#!/usr/bin/env bash

# Mongo
docker run --name pacman-mongo-0 -p 27017:27017 -d mongo --replSet rs0
docker run --name pacman-mongo-1 -p 27018:27017 -d mongo --replSet rs0
docker run --name pacman-mongo-2 -p 27019:27017 -d mongo --replSet rs0
