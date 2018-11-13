#!/usr/bin/env bash
#
# updatedns.sh - Tool to update Gcloud DNS
#
#
#
set -o errexit
set -o nounset
set -o pipefail

source "$(dirname "${BASH_SOURCE}")/../utils/utils.sh"

DST_CONTEXTS=${DST_CONTEXTS:-}

function usage {
    echo "$0: [OPTIONS] [-t|--to-context CONTEXT [CONTEXT]...] [-n|--namespace NAMESPACE] [-z|--zone ZONE_NAME] [-d|--dns DNS_NAME]"
    echo "  Optional Arguments:"
    echo "    -h, --help             Display this usage"
    echo "    -v, --verbose          Increase verbosity for debugging"
    echo "  Required arguments:"
    echo "    -t, --to-context       destination CONTEXTs to migrate DNS"
    echo "    -n, --namespace        namespace containing Kubernetes resources to migrate"
    echo "    -z, --zone             name of zone for your Google Cloud DNS e.g. zonename"
    echo "    -d, --dns              domain name used for your Google Cloud DNS zone e.g. 'example.com.'"
}

function parse-args {
    local req_arg_count=0

    if [[ ${1} == '-h' || ${1} == '--help' ]]; then
        usage
        exit 1
    fi

    while [[ $# -gt 1 ]]; do
        case "${1}" in
            -t|--to-context)
                if [[ -z ${DST_CONTEXTS} ]]; then
                    DST_CONTEXTS="${2}"
                else
                    DST_CONTEXTS+=" ${2}"
                fi
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

    if [[ ${req_arg_count} -lt 4 ]]; then
        echo "Error: missing required arguments"
        usage
        exit 1
    fi

}

function validate-contexts {
    for ctx in ${DST_CONTEXTS}; do
        if ! $(kubectl config get-contexts -o name | grep ${ctx} &> /dev/null); then
            echo "Error: cluster context '${ctx}' is not valid. Please check the context name and try again."
            usage
            exit 1
        fi
    done
}

function validate-namespace {
    for ctx in ${DST_CONTEXTS}; do
        if ! $(kubectl --context=${ctx} get namespace ${NAMESPACE} &> /dev/null); then
            echo "Error: invalid namespace '${NAMESPACE}' for context ${ctx}"
            usage
            exit 1
        fi
    done
}

function validate-zone-name {
    zname=$(gcloud dns managed-zones list --filter="name = ${ZONE_NAME}" --format json | jq -r '.[0].name')

    if [[ ${zname} != ${ZONE_NAME} ]]; then
        echo "Error: invalid zone name '${ZONE_NAME}'"
        usage
        exit 1
    fi
}

function validate-dns-name {
    dname=$(gcloud dns managed-zones list --filter="name = ${ZONE_NAME}" --format json | jq -r '.[0].dnsName')

    if [[ ${dname} != ${DNS_NAME} ]]; then
        echo "Error: invalid DNS name '${DNS_NAME}'"
        usage
        exit 1
    fi
}

function validate-args {
    validate-contexts
    # Disabling namespace validation as it may not exist when this script
    # executes if resources are being migrated by the federation controller.
    #validate-namespace
    validate-zone-name
    validate-dns-name
}

function dns-updated {
    local gcloud_tmpfile=${1}
    local dig_tmpfile=${2}

    DIG_IPS=$(dig ${NAMESPACE}.${DNS_NAME} +short)
    echo ${DIG_IPS} | sed 's/ /\n/g' > ${dig_tmpfile}
    # Check for set equality.
    diff -q <(sort ${gcloud_tmpfile}) <(sort ${dig_tmpfile}) &> /dev/null
}

function verify-dns-update-propagated {
    GCLOUD_DNS_IPS=$(gcloud dns record-sets list -z=${ZONE_NAME} --filter ${NAMESPACE}.${DNS_NAME} | awk -v ns="${NAMESPACE}" '$0 ~ ns {print $4}')
    GCLOUD_DNS_IPS=${GCLOUD_DNS_IPS//,/ }
    if [[ ${NEW_DNS_IPS// /} != ${GCLOUD_DNS_IPS// /} ]]; then
        echo "ERROR: new DNS IPs [${NEW_DNS_IPS}] do not match latest DNS IPs [${GCLOUD_DNS_IPS}]"
        exit 1
    fi

    # Keep checking whether dig shows the updated DNS IP addresses in the list
    # of resolved IP addresses until timeout is reached.
    local script_name=$(basename ${0})
    local gcloud_tmpfile=$(mktemp /tmp/${script_name}.XXXXXX)
    local dig_tmpfile=$(mktemp /tmp/${script_name}.XXXXXX)
    echo ${GCLOUD_DNS_IPS} | sed 's/ /\n/g' > ${gcloud_tmpfile}

    util::wait-for-condition "DNS update" "dns-updated ${gcloud_tmpfile} ${dig_tmpfile}" 180

    rm -f ${gcloud_tmpfile} ${dig_tmpfile}
}

function start-dns-transaction {
    # Abort any existing transactions.
    gcloud dns record-sets transaction abort -z=${ZONE_NAME} 2>/dev/null || true
    echo "Starting transaction on zone [${ZONE_NAME}]..."
    gcloud dns record-sets transaction start -z=${ZONE_NAME}
}

function remove-old-dns-entry {
    # Grab existing IP addresses in DNS entry and replace commas with spaces.
    local old_dns_ips=$(gcloud dns record-sets list -z=${ZONE_NAME} --filter ${NAMESPACE}.${DNS_NAME} | awk -v ns="${NAMESPACE}" '$0 ~ ns {print $4}')
    local old_dns_ips=${old_dns_ips//,/ }

    echo "Removing old IP addresses [${old_dns_ips}] from [${NAMESPACE}.${DNS_NAME}]..."
    gcloud dns record-sets transaction remove \
        -z=${ZONE_NAME} --name="${NAMESPACE}.${DNS_NAME}" \
        --type=A --ttl=1 ${old_dns_ips}
}

function namespace-service-dns-ipaddr-available {
    IP="$(dig ${HOST} +short | head -1)"
    [[ -n ${IP} ]]
}

function add-new-dns-entry {
    local c
    for i in ${DST_CONTEXTS}; do
        util::wait-for-condition "[${NAMESPACE}] service in [${i}]" "util::namespace-service-ready ${i}" 180
        util::wait-for-condition "[${NAMESPACE}] service external host in [${i}]" \
            "util::namespace-service-external-host-ready ${i}" 180

        if [[ -z ${IP} ]]; then
            util::wait-for-condition "load balancer DNS IP address in [${i}]" \
                "namespace-service-dns-ipaddr-available" 180
        fi

        # Exported variable example: GKE_US_WEST1_MYNAMESPACE_IP=xxx.xxx.xxx.xxx
        c=${i^^}
        c=${c//-/_}
        eval ${c}_${NAMESPACE^^}_IP=${IP}
        export ${c}_${NAMESPACE^^}_IP
        echo "${c}_${NAMESPACE^^}_IP: ${IP}"
    done

    # Create a space separated string of IP addresses to be used in the gcloud
    # command in order to add a new DNS entry.
    unset NEW_DNS_IPS
    for i in ${DST_CONTEXTS}; do
        c=${i^^}
        c=${c//-/_}
        local ip=$(echo -n ${c}_${NAMESPACE^^}_IP)
        if [[ -z ${NEW_DNS_IPS} ]]; then
            NEW_DNS_IPS="${!ip}"
        else
            NEW_DNS_IPS+=" ${!ip}"
        fi
    done

    echo "Adding new IP addresses [${NEW_DNS_IPS}] to [${NAMESPACE}.${DNS_NAME}]..."
    gcloud dns record-sets transaction add \
         -z=${ZONE_NAME} --name="${NAMESPACE}.${DNS_NAME}" \
         --type=A --ttl=1 ${NEW_DNS_IPS}
}

function execute-dns-transaction {
    echo "Executing transaction on zone [${ZONE_NAME}]..."
    DNS_TX_ID=$(gcloud dns record-sets transaction execute \
        -z=${ZONE_NAME} | tail -1 | awk '{print $1}')
}

function gcloud-dns-tx-done {
    local status=$(gcloud dns record-sets changes describe \
        -z ${ZONE_NAME} ${1} | awk '/status/ {print $2}')
    [[ "${status}" == "done" ]]
}

function verify-dns-transaction {
    util::wait-for-condition "DNS transaction" "gcloud-dns-tx-done ${DNS_TX_ID}" 180
}

function run-dns-transaction {
    start-dns-transaction
    remove-old-dns-entry
    add-new-dns-entry
    execute-dns-transaction
    verify-dns-transaction
}

function perform-dns-updates {
    echo "Updating [${NAMESPACE}] DNS to use clusters [${DST_CONTEXTS}]..."
    run-dns-transaction
    verify-dns-update-propagated
}

function main {
    parse-args $@
    validate-args
    perform-dns-updates
}

main $@
