#!/usr/bin/env bash
#
# kmt.sh - Kubernetes Migration Tool
#
#
#
set -e

function usage {
    echo "$0: [-f|--from-context CONTEXT] [-t|--to-context CONTEXT] [-n|--namespace NAMESPACE] [-z|--zone ZONE_NAME] [-d|--dns DNS_NAME]"
    echo "    -f, --from-context     source CONTEXT to migrate application"
    echo "    -t, --to-context       destination CONTEXT to migration application"
    echo "    -n, --namespace        namespace containing Kubernetes resources to migrate"
    echo "    -z, --zone             name of zone for your Google Cloud DNS e.g. zonename"
    echo "    -d, --dns              domain name used for your Google Cloud DNS zone e.g. example.com."
}

function parse_args {
    arg_count=0

    while [[ $# -gt 1 ]]; do
        case "${1}" in
            -f|--from-context)
                SRC_CONTEXT="${2}"
                shift
                ;;
            -t|--to-context)
                DST_CONTEXT="${2}"
                shift
                ;;
            -n|--namespace)
                NAMESPACE="${2}"
                shift
                ;;
            -z|--zone)
                ZONE_NAME="${2}"
                shift
                ;;
            -d|--dns)
                DNS_NAME="${2}"
                shift
                ;;
            -h|--help)
                usage
                exit 1
                ;;
            *)
                echo "Error: invalid argument ${arg}"
                usage
                exit 1
                ;;
        esac
        shift
        (( arg_count += 1 ))
    done

    if [[ ${arg_count} -ne 5 ]]; then
        echo "Error: missing required arguments"
        usage
        exit 1
    fi

}

function validate_contexts {
    if ! $(kubectl config get-contexts -o name | grep ${SRC_CONTEXT} &> /dev/null); then
        echo "Error: source context ${SRC_CONTEXT} is not valid. Please check the context name and try again."
        usage
        exit 1
    fi

    if ! $(kubectl config get-contexts -o name | grep ${DST_CONTEXT} &> /dev/null); then
        echo "Error: destination context ${DST_CONTEXT} is not valid. Please check the context name and try again."
        usage
        exit 1
    fi

}

function validate_namespace {
    if ! $(kubectl get namespace ${NAMESPACE} &> /dev/null); then
        echo "Error: invalid namespace ${NAMESPACE}"
        usage
        exit 1
    fi
}

function validate_zone_name {
    zname=$(gcloud dns managed-zones list --filter="name = ${ZONE_NAME}" --format json | jq -r '.[0].name')

    if [[ ${zname} != ${ZONE_NAME} ]]; then
        echo "Error: invalid zone name ${ZONE_NAME}"
        usage
        exit 1
    fi
}

function validate_dns_name {
    dname=$(gcloud dns managed-zones list --filter='name = ifontlabs' --format json | jq -r '.[0].dnsName')

    if [[ ${dname} != ${DNS_NAME} ]]; then
        echo "Error: invalid DNS name ${DNS_NAME}"
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

function main {
    parse_args $@
    validate_args
}

main $@
