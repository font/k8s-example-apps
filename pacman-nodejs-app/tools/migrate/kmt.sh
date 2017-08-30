#!/usr/bin/env bash
#
# kmt.sh - Kubernetes Migration Tool
#
#
#
set -e

function usage {
    echo "$0: [OPTIONS] [-f|--from-context CONTEXT] [-t|--to-context CONTEXT] [-n|--namespace NAMESPACE] [-z|--zone ZONE_NAME] [-d|--dns DNS_NAME]"
    echo "  Optional Arguments:"
    echo "    -h, --help             Display this usage"
    echo "    -v, --verbose          Increase verbosity for debugging"
    echo "  Required arguments:"
    echo "    -f, --from-context     source CONTEXT to migrate application"
    echo "    -t, --to-context       destination CONTEXT to migrate application"
    echo "    -n, --namespace        namespace containing Kubernetes resources to migrate"
    echo "    -z, --zone             name of zone for your Google Cloud DNS e.g. zonename"
    echo "    -d, --dns              domain name used for your Google Cloud DNS zone e.g. 'example.com.'"
}

function parse_args {
    req_arg_count=0

    if [[ ${1} == '-h' || ${1} == '--help' ]]; then
        usage
        exit 1
    fi

    while [[ $# -gt 1 ]]; do
        case "${1}" in
            -f|--from-context)
                SRC_CONTEXT="${2}"
                (( req_arg_count += 1 ))
                shift
                ;;
            -t|--to-context)
                DST_CONTEXT="${2}"
                (( req_arg_count += 1 ))
                shift
                ;;
            -n|--namespace)
                NAMESPACE="${2}"
                (( req_arg_count += 1 ))
                shift
                ;;
            -z|--zone)
                ZONE_NAME="${2}"
                (( req_arg_count += 1 ))
                shift
                ;;
            -d|--dns)
                DNS_NAME="${2}"
                (( req_arg_count += 1 ))
                shift
                ;;
            -v|--verbose)
                set -x
                ;;
            -h|--help)
                usage
                exit 1
                ;;
            *)
                echo "Error: invalid argument '${arg}'"
                usage
                exit 1
                ;;
        esac
        shift
    done

    if [[ ${req_arg_count} -ne 5 ]]; then
        echo "Error: missing required arguments"
        usage
        exit 1
    fi

}

function validate_contexts {
    if ! $(kubectl config get-contexts -o name | grep ${SRC_CONTEXT} &> /dev/null); then
        echo "Error: source context '${SRC_CONTEXT}' is not valid. Please check the context name and try again."
        usage
        exit 1
    fi

    if ! $(kubectl config get-contexts -o name | grep ${DST_CONTEXT} &> /dev/null); then
        echo "Error: destination context '${DST_CONTEXT}' is not valid. Please check the context name and try again."
        usage
        exit 1
    fi

}

function validate_namespace {
    kubectl config use-context ${SRC_CONTEXT}

    if ! $(kubectl get namespace ${NAMESPACE} &> /dev/null); then
        echo "Error: invalid namespace '${NAMESPACE}'"
        usage
        exit 1
    fi
}

function validate_zone_name {
    zname=$(gcloud dns managed-zones list --filter="name = ${ZONE_NAME}" --format json | jq -r '.[0].name')

    if [[ ${zname} != ${ZONE_NAME} ]]; then
        echo "Error: invalid zone name '${ZONE_NAME}'"
        usage
        exit 1
    fi
}

function validate_dns_name {
    dname=$(gcloud dns managed-zones list --filter="name = ${ZONE_NAME}" --format json | jq -r '.[0].dnsName')

    if [[ ${dname} != ${DNS_NAME} ]]; then
        echo "Error: invalid DNS name '${DNS_NAME}'"
        usage
        exit 1
    fi
}

function validate_args {
    validate_contexts
    validate_namespace
    validate_zone_name
    validate_dns_name
}

# Using SOURCE cluster, dump resources into JSON file in temporary directory
function save_src_cluster_resources {
    temp_dir="$(date +%F_%T)-${NAMESPACE}-dump"
    mkdir ${temp_dir}

    kubectl config use-context ${SRC_CONTEXT}

    kubectl get --export -o=json ns | jq ".items[] |
        select(.metadata.name==\"${NAMESPACE}\") |
        del(.status,
            .metadata.uid,
            .metadata.selfLink,
            .metadata.resourceVersion,
            .metadata.creationTimestamp,
            .metadata.generation
           )" > ./${temp_dir}/ns.json

    for ns in $(jq -r '.metadata.name' < ./${temp_dir}/ns.json); do
        kubectl --namespace="${ns}" get --export -o=json pvc,secrets,svc,deploy,rc,ds | \
        jq '.items[] |
            select(.type!="kubernetes.io/service-account-token") |
            del(
                .spec.clusterIP,
                .metadata.uid,
                .metadata.selfLink,
                .metadata.resourceVersion,
                .metadata.creationTimestamp,
                .metadata.generation,
                .metadata.annotations,
                .status,
                .spec.template.spec.securityContext,
                .spec.template.spec.dnsPolicy,
                .spec.template.spec.terminationGracePeriodSeconds,
                .spec.template.spec.restartPolicy,
                .spec.storageClassName,
                .spec.volumeName
            )' > "./${temp_dir}/${ns}-ns-dump.json"
    done

    local services=$(jq -r '(. + select(.kind == "Service") | .metadata.name)' < ./${temp_dir}/${NAMESPACE}-ns-dump.json)

    # Save off public IP addresses/hostnames for services in source cluster
    for s in ${services}; do
        eval ${s^^}_SRC_PUBLIC_ADDRESS=$(kubectl get service ${s} -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
        # Check for hostname (used by AWS, for example) or IP (used by GKE, for example)
        src_ip_var=$(echo ${s^^}_SRC_PUBLIC_ADDRESS)
        if [[ ${!src_ip_var} == '' ]]; then
            eval ${s^^}_SRC_PUBLIC_ADDRESS=$(kubectl get service ${s} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
        fi
    done
}

function create_dst_cluster_resources {
    kubectl config use-context ${DST_CONTEXT}
    kubectl create -f ${temp_dir}/ns.json
    kubectl config set-context ${DST_CONTEXT} --namespace ${NAMESPACE}
    kubectl create -f ./${temp_dir}/${NAMESPACE}-ns-dump.json
}

function verify_services_ready {
    local timeout=120 # wait no more than 2 minutes
    local services=$(jq -r '(. + select(.kind == "Service") | .metadata.name)' < ./${temp_dir}/${NAMESPACE}-ns-dump.json)

    echo -n "Waiting for services [$(echo ${services})]......"

    # Loop until all services have a load balancer IP address or hostname
    local all_ready=false
    while [[ ${all_ready} == false && ${timeout} -gt 0 ]]; do
        all_ready=true

        for s in ${services}; do
            # Filter service load balancer IP address
            local service_address=$(kubectl get service ${s} -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
            if [[ ${service_address} == '' ]]; then
                service_address=$(kubectl get service ${s} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
            fi
            # If we determine that deployment is not ready, try again.
            if [[ ${service_address} == '' ]]; then
                all_ready=false
                break
            fi
        done

        (( timeout -= 5 ))
        sleep 5
    done

    if [[ ${all_ready} == true ]]; then
        echo "READY"
        # Save off public IP addresses/hostnames for services in destination cluster
        for s in ${services}; do
            eval ${s^^}_DST_PUBLIC_ADDRESS=$(kubectl get service ${s} -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
            # Check for hostname (used by AWS, for example) or ip (used by GKE, for example)
            dst_ip_var=$(echo ${s^^}_DST_PUBLIC_ADDRESS)
            if [[ ${!dst_ip_var} == '' ]]; then
                eval ${s^^}_DST_PUBLIC_ADDRESS=$(kubectl get service ${s} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
            fi
        done
    elif [[ ${timeout} -le 0 ]]; then
        echo "WARNING: timeout waiting for services ${services}"
    fi
}

function verify_deployments_ready {
    local timeout=120 # wait no more than 2 minutes
    local deployments=$(jq -r '(. + select(.kind == "Deployment") | .metadata.name)' < ./${temp_dir}/${NAMESPACE}-ns-dump.json)
    echo -n "Waiting for deployments [$(echo ${deployments})]......"

    # Loop until all deployments have the correct number of replicas running
    local all_ready=false
    while [[ ${all_ready} == false && ${timeout} -gt 0 ]]; do
        all_ready=true

        for d in ${deployments}; do
            # Filter deployment whose replica counts do not match i.e. creating
            local not_ready=$(kubectl get deploy/$d -o json | \
                jq '.status | select(.availableReplicas != .readyReplicas) and select(.readyReplicas != .replicas)')
            # If we determine that deployment is not ready, try again.
            if [[ ${not_ready} == true ]]; then
                all_ready=false
                break
            fi
        done
        (( timeout -= 5 ))
        sleep 5
    done

    if [[ ${all_ready} == true ]]; then
        echo "READY"
    elif [[ ${timeout} -le 0 ]]; then
        echo "WARNING: timeout waiting for deployments ${deployments}"
    fi
}

function verify_resources_ready {
    verify_services_ready
    verify_deployments_ready
}

# This function attempts to handle the application specific instructions
# needed to migrate the application appropriately. This function will is
# executed all at once right now, but can eventually support a plugin model
# where application specific code is inserted at particular milestones
# e.g. key intervention points.
function exec_app_recipe {
    source $(dirname ${0})/${NAMESPACE,,}.sh
    exec_app_entrypoint
}

function migrate_resources {
    echo "Migrating ${NAMESPACE} namespace from cluster ${SRC_CONTEXT} to ${DST_CONTEXT}..."
    save_src_cluster_resources
    create_dst_cluster_resources
    sleep 10 # Give it a bit before attempting to verify
    verify_resources_ready
    exec_app_recipe
}

function cleanup {
    kubectl --context ${SRC_CONTEXT} delete ns ${NAMESPACE}
}

function main {
    parse_args $@
    validate_args
    migrate_resources
    cleanup
}

main $@
