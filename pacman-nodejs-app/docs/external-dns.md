# ExternalDNS management of DNS records

This guide will walk you through deploying
[external-dns](https://github.com/kubernetes-incubator/external-dns) and using
it to manage your DNS. `external-dns` provides the ability to program DNS using
numerous DNS providers.

## Google Cloud DNS Managed Zone

For this example, we'll setup a [Google DNS managed
zone](https://cloud.google.com/dns/zones) to hold the DNS entries.

#### Create a Google DNS Managed Zone

The follow command will create a DNS zone named `federation.com`. Specify your own zone name here. In a production setup a valid managed
zone backed by a registered DNS domain should be used.

```bash
DNS_NAME=example.com
gcloud dns managed-zones create federation \
  --description "Kubernetes federation testing" \
  --dns-name ${DNS_NAME}
```

#### Deploy ExternalDNS

We will deploy `external-dns` to the same namespace as the federation controller
manager is running in so that it can use the same permissions necessary to
operate.

Create the deployment for `external-dns` using the necessary arguments to read
the `DNSEndpoint` resource programmed by the federation `DNSEndpoint`
controller along with the `google` provider and DNS domain filter used above.


```bash
cat <<EOF | kubectl create -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: external-dns
  namespace: federation-system
spec:
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: external-dns
  template:
    metadata:
      labels:
        app: external-dns
    spec:
      containers:
      - name: external-dns
        image: registry.opensource.zalan.do/teapot/external-dns:latest
        args:
        - --source=crd
        - --crd-source-apiversion=multiclusterdns.federation.k8s.io/v1alpha1
        - --crd-source-kind=DNSEndpoint
        - --policy=sync
        - --provider=google
        - --domain-filter=${DNS_NAME}
        - --registry=txt
        - --txt-owner-id=my-identifier
        - --txt-prefix=txt
EOF
```

#### Create ServiceDNSRecord

Now we need to create the resource that tells the `ServiceDNS` controller to
update the status with the load balancer information so that the `DNSEndpoint`
controller can watch for that load balancer information. The `DNSEndpoint`
controller subsequently writes the corresponding `DNSEndpoint` resource so that
`external-dns` can pick it up and program the DNS entries using the configured
DNS provider.

```bash
cat <<EOF | kubectl create -f -
apiVersion: multiclusterdns.federation.k8s.io/v1alpha1
kind: MultiClusterServiceDNSRecord
metadata:
  name: pacman
spec:
  dnsSuffix: ${DNS_NAME}
  federationName: federation
  recordTTL: 1
EOF
```

If you experience any difficulties here, you can troubleshoot by checking the
status of the above resource as well as the `DNSEndoint resource`:

```bash
kubectl get multiclusterservicednsrecord pacman -o yaml
kubectl get dnsendpoint service-pacman -o yaml
```

#### Create Short DNS Entry for Application

In order to have an easy to use URL, let's add a simple `pacman.example.com`
DNS entry:

```bash
ZONE_NAME=zonename
gcloud dns record-sets transaction start -z=${ZONE_NAME}
gcloud dns record-sets transaction add \
    -z=${ZONE_NAME} --name="pacman.${DNS_NAME}" \
    --type=CNAME --ttl=1 pacman.pacman.federation.svc.${DNS_NAME}.
gcloud dns record-sets transaction execute -z=${ZONE_NAME}
```

## Cleanup

#### Remove Short DNS Entry for Application

```bash
gcloud dns record-sets transaction start -z=${ZONE_NAME}
gcloud dns record-sets transaction remove \
    -z=${ZONE_NAME} --name="pacman.${DNS_NAME}" \
    --type=CNAME --ttl=1 pacman.pacman.federation.svc.${DNS_NAME}.
gcloud dns record-sets transaction execute -z=${ZONE_NAME}
```

#### Delete ServiceDNSRecord

```bash
kubectl delete multiclusterservicednsrecord pacman
```

#### Delete ExternalDNS Deployment

```bash
kubectl -n federation-system delete deploy external-dns
```

#### Delete Google DNS Managed Zone

The managed zone must be empty before you can delete it. Visit the [Google DNS
console](https://console.cloud.google.com/networking/dns/zones) and delete all
resource records before running the following command:

```bash
gcloud dns managed-zones delete federation
```
