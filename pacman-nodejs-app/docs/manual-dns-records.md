# Manual DNS Records

This document is intended to be linked from within tutorials for those users wanting
to manually create DNS records.

## Create DNS records

In order to create DNS records, we need to grab each of the load balancer IP
addresses for the pacman service in each of the clusters.

```bash
for i in ${CLUSTERS}; do
    IP=$(kubectl --context=${i} get svc pacman -o \
        jsonpath='{.status.loadBalancer.ingress[0].ip}')
    if [[ -z ${IP} ]]; then
        HOST=$(kubectl --context=${i} get svc pacman -o \
            jsonpath='{.status.loadBalancer.ingress[0].hostname}')
        IP="$(dig ${HOST} +short | head -1)"
    fi
    i=${i^^}
    i=${i//-/_}
    eval ${i}_PACMAN_IP=${IP}
    export ${i}_PACMAN_IP
    echo "${i}_PACMAN_IP: ${IP}"
done
```

Set the value of your `ZONE_NAME` and `DNS_NAME` used for your Google Cloud DNS configuration.

```bash
ZONE_NAME=zonename
DNS_NAME=example.com.
```

Then execute the below commands:

```bash
gcloud dns record-sets transaction start -z=${ZONE_NAME}
unset PACMAN_IPS
for i in ${CLUSTERS}; do
    i=${i^^}
    i=${i//-/_}
    IP=$(echo -n ${i}_PACMAN_IP)
    PACMAN_IPS+=" ${!IP}"
done
gcloud dns record-sets transaction add \
    -z=${ZONE_NAME} --name="pacman.${DNS_NAME}" \
    --type=A --ttl=1 ${PACMAN_IPS}
gcloud dns record-sets transaction execute -z=${ZONE_NAME}
```

## Delete DNS records

Delete the `pacman` and possibly any `mongo` DNS entries that were created in your
[Google DNS Managed Zone](https://console.cloud.google.com/networking/dns/zones).
