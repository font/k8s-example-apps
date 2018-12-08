#!/usr/bin/env bash
#
# updatelb.sh - Tool to update HAProxy L7 Load Balancer
#
#
#
set -o errexit
set -o nounset
set -o pipefail

source "$(dirname "${BASH_SOURCE}")/../utils/utils.sh"

DST_CONTEXTS=${DST_CONTEXTS:-}

function usage {
    echo "$0: [OPTIONS] [-t|--to-context CONTEXT [CONTEXT]...] [-n|--namespace NAMESPACE]"
    echo "  Optional Arguments:"
    echo "    -h, --help             Display this usage"
    echo "    -v, --verbose          Increase verbosity for debugging"
    echo "  Required arguments:"
    echo "    -t, --to-context       destination CONTEXTs to migrate load balancer"
    echo "    -n, --namespace        namespace containing Kubernetes resources to migrate"
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

    if [[ ${req_arg_count} -lt 2 ]]; then
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

function validate-args {
    validate-contexts
    # Disabling namespace validation as it may not exist when this script
    # executes if resources are being migrated by the federation controller.
    #validate_namespace
}

function namespace-service-dns-ipaddr-available {
    # Use Google's public DNS server as all we care about is the IP address to
    # program the load balancer.
    IP="$(dig ${HOST} +short @8.8.8.8 | head -1)"
    [[ -n ${IP} ]]
}

HAPROXY_POD=${HAPROXY_POD:-}
# Run the HAProxy command argument against the Runtime API.
function run-haproxy-cmd {
    if [[ -z ${HAPROXY_POD} ]]; then
        HAPROXY_POD=$(kubectl -n haproxy get pod \
            --selector="app=haproxy" \
            --output=jsonpath='{.items..metadata.name}')
    fi

    kubectl -n haproxy exec -it ${HAPROXY_POD} -- \
        bash -c "echo '${1}' | socat stdio /tmp/haproxy"
}

function set-lb-server-entry {
    local cluster region new_server_ip
    declare -A backends

    # Grab and export IP addresses for load balancer IP or hostname for each
    # cluster.
    for i in ${DST_CONTEXTS}; do
        util::wait-for-condition "[${NAMESPACE}] service in [${i}]" "util::namespace-service-ready ${i}" 180
        util::wait-for-condition "[${NAMESPACE}] service external host in [${i}]" \
            "util::namespace-service-external-host-ready ${i}" 180

        if [[ -z ${IP} ]]; then
            util::wait-for-condition "load balancer DNS IP address in [${i}]" \
                "namespace-service-dns-ipaddr-available" 180
        fi

        # Exported variable example: GKE_US_WEST1_MYNAMESPACE_IP=xxx.xxx.xxx.xxx
        cluster=${i^^}
        cluster=${cluster//-/_}
        eval ${cluster}_${NAMESPACE^^}_IP=${IP}
        export ${cluster}_${NAMESPACE^^}_IP
        echo "${cluster}_${NAMESPACE^^}_IP: ${IP}"
    done

    # Update the HAProxy config to use the respective load balancer IP
    # addresses for each cluster.
    for i in ${DST_CONTEXTS}; do
        cluster=${i^^}
        cluster=${cluster//-/_}
        region=$(echo ${i##*-})
        region=$(echo ${region::-1})
        local ip=$(echo -n ${cluster}_${NAMESPACE^^}_IP)
        new_server_ip="${!ip}"
        echo "Setting ${i} (${region}) IP address to [${new_server_ip}]..."
        run-haproxy-cmd "set server pacman_web_servers/${region} addr ${new_server_ip}"
        run-haproxy-cmd "set server pacman_web_servers/${region} state ready"
        backends[${region}]="ready"
    done

    # Check which servers we need to disable and disable it.
    for r in west central east; do
        if [[ ! -v backends[${r}] ]]; then
            run-haproxy-cmd "set server pacman_web_servers/${r} state maint"
        fi
    done
}

function perform-lb-updates {
    echo "Updating L7 load balancer for [${NAMESPACE}] to use clusters [${DST_CONTEXTS}]..."
    set-lb-server-entry
}

function main {
    parse-args $@
    validate-args
    perform-lb-updates
}

main $@
