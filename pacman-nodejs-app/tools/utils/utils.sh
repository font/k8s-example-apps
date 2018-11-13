# Bash utility functions

# util::wait-for-condition blocks until the provided condition becomes true
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
function util::wait-for-condition() {
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
readonly -f util::wait-for-condition

function util::namespace-service-ready {
    kubectl --context=${1} get svc ${NAMESPACE} -o wide &> /dev/null
}
readonly -f util::namespace-service-ready

function util::namespace-service-external-host-ready {
    IP=$(kubectl --context=${1} get svc ${NAMESPACE} -o \
        jsonpath='{.status.loadBalancer.ingress[0].ip}')

    if [[ -z ${IP} ]]; then
        HOST=$(kubectl --context=${1} get svc ${NAMESPACE} -o \
            jsonpath='{.status.loadBalancer.ingress[0].hostname}')
        [[ -n ${HOST} ]]
    fi
}
readonly -f util::namespace-service-external-host-ready
