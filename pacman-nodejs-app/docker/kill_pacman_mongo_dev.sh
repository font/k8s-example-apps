#!/usr/bin/env bash

# Mongo
docker kill pacman-mongo-0 pacman-mongo-1 pacman-mongo-2
docker rm pacman-mongo-0 pacman-mongo-1 pacman-mongo-2
