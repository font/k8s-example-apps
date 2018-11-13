#!/usr/bin/env bash

TEST_CLUSTERS="aws-us-east1 az-us-central1"
LOOP_INTERVAL=10 # in minutes
count=0

while true; do

    echo -e "count ${count}"
    # Migrate from Azure to AWS and back
    for i in ${TEST_CLUSTERS}; do
        echo "---------- ${i} -----------"
        set -x
        kubectl patch federatednamespaceplacement pacman --type=merge -p \
            "{\"spec\":{\"clusterNames\": [\"gke-us-west1\", \"az-us-central1\", \"aws-us-east1\"]}}"
        set +x
        time updatedns -t gke-us-west1 -t ${i}
        set -x
        kubectl patch federatednamespaceplacement pacman --type=merge -p \
            "{\"spec\":{\"clusterNames\": [\"gke-us-west1\", \"${i}\"]}}"
        set +x
    done
    echo -e "\n\n\n"
    sleep ${LOOP_INTERVAL}m
    (( count += 1 ))
done
