# HAProxy L7 Load Balancer

This document is intended to be linked from within tutorials for those users
wanting to deploy an L7 load balancer with a DNS record to point to it in order
to play the game.

## Create HAProxy Resources

In order to deploy HAProxy, we need to create a templated configuration
file as a ConfigMap and then deploy the Deployment and Service resources for
HAProxy with a volume mount for the config file referencing the ConfigMap.

First we need to create a new namespace to contain all these resources:

```bash
kubectl create ns haproxy
```

Next, let's create the ConfigMap for the HAProxy config:

```bash
kubectl -n haproxy create configmap haproxy-cfg --from-file=lb/haproxy.cfg
```

Now with the config file available, let's create the rest of the HAProxy
resources:

```bash
kubectl -n haproxy create -f lb/haproxy.yaml
```

## Configure HAProxy Servers

The initially deployed HAProxy configuration creates templated servers that are
in maintenance so the backend is effectively down. So we need to set the
appropriate IP addresses or hostnames for the servers and set their state as
`READY` in order to start forwarding traffic. We will use the HAProxy Runtime
API to make these changes.

We'll be running commands within the HAProxy pod to modify the configuration at
runtime. First we need to grab and set some variables:

```bash
HOST_CLUSTER=gke-us-west1
HAPROXY_POD=$(kubectl --context=${HOST_CLUSTER} -n haproxy get pod \
    --selector="app=haproxy" \
    --output=jsonpath='{.items..metadata.name}')
```

Now let's configure HAProxy to forward to each pacman load balancer IP or
hostname in each cluster.

```bash
for i in ${CLUSTERS}; do
    IP_OR_HOST=$(kubectl --context=${i} get svc pacman -o \
        jsonpath='{.status.loadBalancer.ingress[0].ip}')
    if [[ -z ${IP_OR_HOST} ]]; then
        IP_OR_HOST=$(kubectl --context=${i} get svc pacman -o \
            jsonpath='{.status.loadBalancer.ingress[0].hostname}')
        IP_OR_HOST="$(dig ${IP_OR_HOST} +short | head -1)"
    fi
    SERVER=$(echo ${i##*-})
    SERVER=$(echo ${SERVER::-1})
    echo "${i} (${SERVER}): ${IP_OR_HOST}"
    kubectl --context=${HOST_CLUSTER} -n haproxy \
        exec -it ${HAPROXY_POD} -- \
        bash -c "echo 'set server pacman_web_servers/${SERVER} addr ${IP_OR_HOST}' \
                       | socat stdio /tmp/haproxy"
    kubectl --context=${HOST_CLUSTER} -n haproxy \
        exec -it ${HAPROXY_POD} -- \
        bash -c "echo 'set server pacman_web_servers/${SERVER} state ready' \
                       | socat stdio /tmp/haproxy"
done
```

## Create DNS record for HAProxy Load Balancer

To make the load balancer easily accessible, let's create a DNS A record with
its IP address.

Set the value of your `ZONE_NAME` and `DNS_NAME` used for your Google Cloud DNS
configuration as well as the `HAPROXY_IP` for the HAProxy load balancer IP
address.

```bash
ZONE_NAME=zonename
DNS_NAME=example.com.
HAPROXY_IP=$(kubectl --context=${HOST_CLUSTER} -n haproxy get svc haproxy -o \
        jsonpath='{.status.loadBalancer.ingress[0].ip}')
```

Verify the `HAPROXY_IP` variable from the command above has been properly set.
If not, you'll need to wait for the `haproxy` service to obtain an external
load balancer IP address.

Then execute the below commands:

```bash
gcloud dns record-sets transaction start -z=${ZONE_NAME}
gcloud dns record-sets transaction add \
    -z=${ZONE_NAME} --name="pacman.${DNS_NAME}" \
    --type=A --ttl=1 ${HAPROXY_IP}
gcloud dns record-sets transaction execute -z=${ZONE_NAME}
```

## Cleanup

To cleanup HAProxy run the following commands:

```bash
kubectl delete ns haproxy
```

Then delete the `pacman` DNS entry that was created in your
[Google DNS Managed Zone](https://console.cloud.google.com/networking/dns/zones).
