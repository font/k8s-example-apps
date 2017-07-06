#!/usr/bin/env bash
set -e

function add_new_mongo_instance {
    MONGO_SRC_POD=$(kubectl --context ${SRC_CONTEXT} get pod \
    --selector="name=mongo" --output=jsonpath='{.items..metadata.name}')

    kubectl --context ${SRC_CONTEXT} exec -it -- \
        mongo --eval "rs.add(\"${MONGO_DST_PUBLIC_IP}:27017\")"
}

function check_mongo_status {
    local timeout=120 # wait no more than 2 minutes
    local context=${1}
    local pod=${2}
    local member=${3}
    local mongo_ip=${4}
    local status=${5}

    while [[ ${timeout} -gt 0 ]]; do
        mongo_status=$(kubectl --context ${context} exec -it ${pod} -- \
            mongo --quiet --eval "JSON.stringify(rs.status())" | jq -r ".members[${member}].stateStr")

        if [[ ${mongo_status} =~ ${status} ]]; then
            echo "Mongo instance ${mongo_ip} is now ${status}"
            break;
        fi

        (( timeout-- ))
        sleep 1
    done
}

function set_new_mongo_primary {
    kubectl --context ${SRC_CONTEXT} exec -it ${MONGO_SRC_POD} -- \
        mongo --eval "rs.stepDown(120)"
}

function update_pacman_dns {
    gcloud dns record-sets transaction start -z=${ZONE_NAME}
    gcloud dns record-sets transaction remove -z=${ZONE_NAME} \
        --name="pacman.${DNS_NAME}" --type=A --ttl=1 "${PACMAN_SRC_PUBLIC_IP}"
    gcloud dns record-sets transaction add -z=${ZONE_NAME} \
        --name="pacman.${DNS_NAME}" --type=A --ttl=1 "${PACMAN_DST_PUBLIC_IP}"
    gcloud dns record-sets transaction execute -z=${ZONE_NAME}
}

function remove_old_mongo_instance {
    MONGO_DST_POD=$(kubectl --context ${DST_CONTEXT} get pod \
        --selector="name=mongo" \
        --output=jsonpath='{.items..metadata.name}')

    kubectl --context ${DST_CONTEXT} exec -it ${MONGO_DST_POD} -- \
        mongo --eval "rs.remove(\"${MONGO_SRC_PUBLIC_IP}:27017\")"
}

function exec_app_entrypoint {
    add_new_mongo_instance
    check_mongo_status ${SRC_CONTEXT} ${MONGO_SRC_POD} 1 ${MONGO_DST_PUBLIC_IP} 'SECONDARY'
    set_new_mongo_primary
    check_mongo_status ${DST_CONTEXT} ${MONGO_DST_POD} 0 ${MONGO_DST_PUBLIC_IP} 'PRIMARY'
    update_pacman_dns
    remove_old_mongo_instance
    sleep 5 # Wait for things to stabilize
}
