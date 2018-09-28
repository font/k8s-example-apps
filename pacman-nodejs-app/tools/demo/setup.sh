#!/usr/bin/env bash

set -x
kubectl patch federatednamespaceplacement pacman -p \
    '{"spec":{"clusterNames": ["gke-us-west1", "az-us-central1"]}}'
set +x
updatedns -t gke-us-west1 -t az-us-central1
