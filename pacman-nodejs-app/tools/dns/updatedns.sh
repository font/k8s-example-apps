#!/usr/bin/env bash
#
# updatedns.sh - Tool to update Gcloud DNS
#
#
#
set -e

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

function parse_args {
    req_arg_count=0

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

function validate_contexts {
    for ctx in ${DST_CONTEXTS}; do
        if ! $(kubectl config get-contexts -o name | grep ${ctx} &> /dev/null); then
            echo "Error: cluster context '${ctx}' is not valid. Please check the context name and try again."
            usage
            exit 1
        fi
    done
}

function validate_namespace {
    for ctx in ${DST_CONTEXTS}; do
        if ! $(kubectl --context=${ctx} get namespace ${NAMESPACE} &> /dev/null); then
            echo "Error: invalid namespace '${NAMESPACE}' for context ${ctx}"
            usage
            exit 1
        fi
    done
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
    #validate_namespace
    validate_zone_name
    validate_dns_name
}

function dns-updated {
    local gcloud_tmpfile=${1}
    local dig_tmpfile=${2}

    DIG_IPS=$(dig ${NAMESPACE}.${DNS_NAME} +short)
    echo ${DIG_IPS} | sed 's/ /\n/g' > ${dig_tmpfile}
    # Check for set equality.
    diff -q <(sort ${gcloud_tmpfile}) <(sort ${dig_tmpfile}) &> /dev/null
}

function verify_dns_update_propagated {
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

    wait-for-condition "DNS update" "dns-updated ${gcloud_tmpfile} ${dig_tmpfile}" 180

    rm -f ${gcloud_tmpfile} ${dig_tmpfile}
}

function start_dns_transaction {
    # Abort any existing transactions.
    gcloud dns record-sets transaction abort -z=${ZONE_NAME} 2>/dev/null || true
    echo "Starting transaction on zone [${ZONE_NAME}]..."
    gcloud dns record-sets transaction start -z=${ZONE_NAME}
}

function remove_old_dns_entry {
    # Grab existing IP addresses in DNS entry and replace commas with spaces.
    local old_dns_ips=$(gcloud dns record-sets list -z=${ZONE_NAME} --filter ${NAMESPACE}.${DNS_NAME} | awk -v ns="${NAMESPACE}" '$0 ~ ns {print $4}')
    local old_dns_ips=${old_dns_ips//,/ }

    echo "Removing old IP addresses [${old_dns_ips}] from [${NAMESPACE}.${DNS_NAME}]..."
    gcloud dns record-sets transaction remove \
        -z=${ZONE_NAME} --name="${NAMESPACE}.${DNS_NAME}" \
        --type=A --ttl=1 ${old_dns_ips}
}

# wait-for-condition blocks until the provided condition becomes true
#
# Globals:
#  None
# Arguments:
#  - 1: message indicating what conditions is being waited for (e.g. 'config to be written')
#  - 2: a string representing an eval'able condition.  When eval'd it should not output
#       anything to stdout or stderr.
#  - 3: optional timeout in seconds.  If not provided, waits forever.
# Returns:
#  1 if the condition is not met before the timeout
function wait-for-condition() {
  local msg=$1
  # condition should be a string that can be eval'd.
  local condition=$2
  local timeout=${3:-}
  local sleep_secs=5

  local start_msg="Waiting for ${msg}.."
  local error_msg="[ERROR] Timeout waiting for ${msg}"

  local counter=0
  while ! ${condition}; do
    if [[ "${counter}" = "0" ]]; then
      echo -n "${start_msg}"
    fi

    if [[ -z "${timeout}" || "${counter}" -lt "${timeout}" ]]; then
      counter=$((counter + ${sleep_secs}))
      if [[ -n "${timeout}" ]]; then
        echo -n '.'
      fi
      sleep ${sleep_secs}
    else
      echo -e "\n${error_msg}"
      return 1
    fi
  done

  if [[ "${counter}" != "0" && -n "${timeout}" ]]; then
    echo 'OK'
  fi
}

function namespace-service-ready {
    kubectl --context=${1} get svc ${NAMESPACE} -o wide &> /dev/null
}

function namespace-service-external-host-ready {
    IP=$(kubectl --context=${1} get svc ${NAMESPACE} -o \
        jsonpath='{.status.loadBalancer.ingress[0].ip}')

    if [[ -z ${IP} ]]; then
        HOST=$(kubectl --context=${1} get svc ${NAMESPACE} -o \
            jsonpath='{.status.loadBalancer.ingress[0].hostname}')
        [[ -n ${HOST} ]]
    fi
}

function namespace-service-dns-ipaddr-available {
    IP="$(dig ${HOST} +short | head -1)"
    [[ -n ${IP} ]]
}

function add_new_dns_entry {
    local c
    for i in ${DST_CONTEXTS}; do
        wait-for-condition "[${NAMESPACE}] service in [${i}]" "namespace-service-ready ${i}" 180
        wait-for-condition "[${NAMESPACE}] service external host in [${i}]" \
            "namespace-service-external-host-ready ${i}" 180

        if [[ -z ${IP} ]]; then
            wait-for-condition "load balancer DNS IP address in [${i}]" \
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

function execute_dns_transaction {
    echo "Executing transaction on zone [${ZONE_NAME}]..."
    DNS_TX_ID=$(gcloud dns record-sets transaction execute \
        -z=${ZONE_NAME} | tail -1 | awk '{print $1}')
}

function gcloud-dns-tx-done {
    local status=$(gcloud dns record-sets changes describe \
        -z ${ZONE_NAME} ${1} | awk '/status/ {print $2}')
    [[ "${status}" == "done" ]]
}

function verify_dns_transaction {
    wait-for-condition "DNS transaction" "gcloud-dns-tx-done ${DNS_TX_ID}" 180
}

function run_dns_transaction {
    start_dns_transaction
    remove_old_dns_entry
    add_new_dns_entry
    execute_dns_transaction
    verify_dns_transaction
}

function perform_dns_updates {
    echo "Updating [${NAMESPACE}] DNS to use clusters [${DST_CONTEXTS}]..."
    run_dns_transaction
    verify_dns_update_propagated
}

function main {
    parse_args $@
    validate_args
    perform_dns_updates
}

main $@
