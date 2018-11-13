#!/usr/bin/env bash

TEST_CLUSTERS="aws-us-east1 az-us-central1"
OUTER_LOOP_INTERVAL=10 # in minutes
INNER_LOOP_INTERVAL=30 # in seconds
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
        time updatelb -t gke-us-west1 -t ${i}
        set -x
        kubectl patch federatednamespaceplacement pacman --type=merge -p \
            "{\"spec\":{\"clusterNames\": [\"gke-us-west1\", \"${i}\"]}}"
        sleep ${INNER_LOOP_INTERVAL}
        set +x
    done
    echo -e "\n\n\n"
    sleep ${OUTER_LOOP_INTERVAL}m
    (( count += 1 ))
done
