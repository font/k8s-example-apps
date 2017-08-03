#!/usr/bin/env bash
set -e

function add_new_mongo_instance {
    MONGO_SRC_POD=$(kubectl --context ${SRC_CONTEXT} get pod \
    --selector="name=mongo" --output=jsonpath='{.items..metadata.name}')

    MONGO_DST_POD=$(kubectl --context ${DST_CONTEXT} get pod \
        --selector="name=mongo" \
        --output=jsonpath='{.items..metadata.name}')

    kubectl --context ${SRC_CONTEXT} exec -it ${MONGO_SRC_POD} -- \
        mongo --eval "rs.add(\"${MONGO_DST_PUBLIC_IP}:27017\")"
}

function check_mongo_status {
    local timeout=120 # wait no more than 2 minutes
    local context=${1}
    local pod=${2}
    local mongo_ip=${3}
    local status=${4}

    while [[ ${timeout} -gt 0 ]]; do
        mongo_status=$(kubectl --context ${context} exec -it ${pod} -- \
            mongo --quiet --eval "JSON.stringify(rs.status())" | \
            jq -r ".members[] | select(.name ==\"${mongo_ip}:27017\") | .stateStr")

        if [[ ${mongo_status} =~ ${status} ]]; then
            echo "Mongo instance ${mongo_ip} is now ${status}"
            break;
        fi

        (( timeout -= 5 ))
        sleep 5
    done
}

function set_new_mongo_primary {
    # Succeed even if it fails as mongo fails with benign error:
    # Error: error doing query: failed: network error while attempting to run
    #        command 'replSetStepDown' on host '127.0.0.1:27017'
    kubectl --context ${SRC_CONTEXT} exec -it ${MONGO_SRC_POD} -- \
        mongo --eval "rs.stepDown(120)" || true
}

function valid_ip {
    local ip=$1
    local rc=1

    if [[ ${ip} =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=${IFS}
        IFS='.'
        ip=(${ip})
        IFS=${OIFS}
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && ${ip[2]} -le 255
            && ${ip[3]} -le 255 ]]
        rc=$?
    fi

    return ${rc}
}


# TODO: make DNS management generic enough for all applications
function update_pacman_dns {
    	gcloud dns record-sets transaction start -z=${ZONE_NAME}
	echo ${PACMAN_SRC_PUBLIC_IP}
	echo ${ZONE_NAME}
	echo ${DNS_NAME}
	if valid_ip ${PACMAN_SRC_PUBLIC_IP} ; then 
    		gcloud dns record-sets transaction remove "${PACMAN_SRC_PUBLIC_IP}"
		--zone=${ZONE_NAME} --name="pacman.${DNS_NAME}" --type=A --ttl=1 
	else	gcloud dns record-sets transaction remove "${PACMAN_SRC_PUBLIC_IP}." \
			--zone=${ZONE_NAME} --name="pacman.${DNS_NAME}" --type=CNAME --ttl=1
	fi
    gcloud dns record-sets transaction add -z=${ZONE_NAME} \
        --name="pacman.${DNS_NAME}" --type=A --ttl=1 "${PACMAN_DST_PUBLIC_IP}"
    gcloud dns record-sets transaction execute -z=${ZONE_NAME}
}

function remove_old_mongo_instance {
    kubectl --context ${DST_CONTEXT} exec -it ${MONGO_DST_POD} -- \
        mongo --eval "rs.remove(\"${MONGO_SRC_PUBLIC_IP}:27017\")"
}

function exec_app_entrypoint {
    add_new_mongo_instance
    check_mongo_status ${SRC_CONTEXT} ${MONGO_SRC_POD} ${MONGO_DST_PUBLIC_IP} 'SECONDARY'
    set_new_mongo_primary
    check_mongo_status ${DST_CONTEXT} ${MONGO_DST_POD} ${MONGO_DST_PUBLIC_IP} 'PRIMARY'
    update_pacman_dns
    remove_old_mongo_instance
    sleep 5 # Wait for things to stabilize
}
