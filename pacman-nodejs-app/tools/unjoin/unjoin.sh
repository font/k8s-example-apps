#!/bin/bash

function usage {
    echo "${0} [host-context] [cluster-context]"
}

if [[ $# -ne 2 ]]; then
    echo "ERROR: Required arg(s) missing"
    usage
    exit 1
fi

HOST_CTX=${1}
JOIN_CTX=${2}

kubectl --context=${JOIN_CTX} delete sa ${JOIN_CTX}-${HOST_CTX} -n federation
kubectl --context=${JOIN_CTX} delete clusterrolebinding federation-controller-manager:${JOIN_CTX}-${HOST_CTX}
kubectl --context=${JOIN_CTX} delete clusterrole federation-controller-manager:${JOIN_CTX}-${HOST_CTX}

kubectl --context=${HOST_CTX} delete clusters ${JOIN_CTX}
kubectl --context=${HOST_CTX} delete federatedclusters ${JOIN_CTX}

if [[ ${HOST_CTX} != ${JOIN_CTX} ]]; then
    kubectl --context=${JOIN_CTX} delete ns federation
fi
