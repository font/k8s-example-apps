# Federated Kubernetes Tutorial

This tutorial will walk you through setting up a Kubernetes cluster federation using `kubefed` with multiple public cloud providers.

## Prerequisites

#### Kubernetes Clusters Created

The Kubernetes clusters that you plan to use to create the federation should already be created. If not, please
follow steps to create them using [GKE](kubernetes-cluster-gke-federation.md), [AWS](kubernetes-cluster-aws.md),
and [Azure](kubernetes-cluster-azure.md).

#### Cluster DNS Managed Zone Created

You should already have a Kubernetes cluster DNS Managed Zone. See
[these instructions for an example of creating one with Google Cloud DNS](kubernetes-cluster-gke-federation.md#cluster-dns-managed-zone).

#### kubectl and kubefed installed

The `kubectl` and `kubefed` commands should already be installed. You should match the version of these tools to the version of Kubernetes
your clusters are running.

```bash
kubectl version
kubefed version
```

#### kubectl configured

The `kubectl` command should already have access to the kubeconfig or contexts for each cluster you're going to add to the federation.

To verify, list the contexts stored in your kubeconfig. These will be used later by the `kubefed` command.

```bash
kubectl config get-contexts --output=name
```

#### Store the GCP Project Name

If you're planning to use at least 1 GKE cluster, you'll want to save your project ID in a handy variable:

```bash
export GCP_PROJECT=$(gcloud config list --format='value(core.project)')
```

## Configure Kubernetes Federation Host Cluster

Out of the lists of contexts available to `kubectl` from the command above, select the context you want to use to host the Kubernetes
federation control plane. For example, using a GKE cluster in the us-west region:

```bash
HOST_CLUSTER=gke_${GCP_PROJECT}_us-west1-b_gce-us-west1
```

## Configure Kubernetes Federation Clusters to Join

Out of the lists of contexts available to `kubectl` from the command above, select the contexts you want to join to the Kubernetes
federation. For example, using the GKE host cluster in the us-west region, an Azure cluster in the us-central region, and an AWS cluster
in the us-east region with their corresponding context names:

```bash
JOIN_CLUSTERS="${HOST_CLUSTER} az-us-central1 us-east-1.subdomain.example.com"
```

## Initialize the Federated Control Plane

Initialization is easy with the `kubefed init` command. We will use the `HOST_CLUSTER` context to host our federated control plane.
Replace the `--dns-zone-name` parameter to match the DNS zone name you used when you created your DNS zone.
**Be sure to include the trailing `.` in the DNS zone name**.

`kubefed init` will set some defaults if you do not override them on the command line.
For example, `--dns-provider='google-clouddns'` is set by default in Kubernetes versions <= 1.5. However, starting with `kubefed` version
1.6, this argument is mandatory. Additionally, you can pass `--image='gcr.io/google_containers/hyperkube-amd64:v1.5.6'`
to specify a different version of the federation API server and controller manager. By default, the image version it pulls will
match the version of `kubefed` you are using.

```bash
kubefed init federation \
    --host-cluster-context=${HOST_CLUSTER} \
    --dns-provider=google-clouddns \
    --dns-zone-name=federation.com.
```

Once the command completes, you will have a federated API server and controller-manager running in the `HOST_CLUSTER` zone, in addition
to a `federation` context for `kubectl` commands.

## Join the Kubernetes Clusters to the Federation

We'll use `kubefed join` to join each of the Kubernetes clusters. We need to specify in which context the federaton control plane
is running using the `--host-cluster-context` parameter as well as the context of the Kubernetes cluster we're joining to the federation using
the `--cluster-context` parameter.

#### Use federation context

Before proceeding, make sure we're using the newly created `federation` context to run our `kubefed join` commands.

```bash
kubectl config use-context federation
```

#### Join Individual Clusters

If you want to join each cluster individually such as to give it a unique name, then join each one like so:

##### gce-us-west1

```bash
kubefed join gce-us-west1 \
    --host-cluster-context=${HOST_CLUSTER} \
    --cluster-context=${HOST_CLUSTER}
```

##### az-us-central1

```bash
kubefed join az-us-central1 \
    --host-cluster-context=${HOST_CLUSTER} \
    --cluster-context=az-us-central1
```

##### aws-us-east1

```bash
kubefed join aws-us-east1 \
    --host-cluster-context=${HOST_CLUSTER} \
    --cluster-context=us-east-1.subdomain.example.com
```

#### Verify

```bash
kubectl get clusters -w
```

## Update KubeDNS

Lastly, now that the federated cluster is up and ready, we need to update kube-dns in each cluster to specify the federation domain name.
Unfortunately, this is a manual step that `kubefed` does not do for you yet unless you're using Kubernetes 1.6 release. See Kubernetes issue #38400
and PR #39338 for more details.

To update the kube-dns we will add a config map to the kube-dns namespace in each cluster specifying the federation domain name.

#### Replace federation zone name

Before running the below command make sure to replace `federation.com` with the zone name you specified when creating your
DNS Managed Zone.

```bash
sed 's/federation.com/YOUR_ZONE_NAME/' configmap/federation-cm.yaml > tmp \
    && mv -f tmp configmap/federation-cm.yaml
```

#### Create the Config Map For All Clusters

```bash
for c in ${JOIN_CLUSTERS}; do
    kubectl --context=${c} \
        --namespace=kube-system \
        create -f configmap/federation-cm.yaml
done
```

```bash
for c in ${JOIN_CLUSTERS}; do
    kubectl --context=${c} \
        --namespace=kube-system \
        get configmap kube-dns -o yaml
done
```

You should now have a working federated Kubernetes cluster spanning each zone.

## Cleanup

Cleanup is basically some of the setup steps in reverse.

#### Unjoin Individual Clusters

If you joined each cluster individually by providing a unique name to each, then unjoin each one like so:

##### gce-us-west1

```bash
kubefed unjoin gce-us-west1 \
    --host-cluster-context=${HOST_CLUSTER}
```

##### az-us-central1

```bash
kubefed unjoin az-us-central1 \
    --host-cluster-context=${HOST_CLUSTER}
```

##### aws-us-east1

```bash
kubefed unjoin aws-us-east1 \
    --host-cluster-context=${HOST_CLUSTER}
```

#### Delete federation control plane

Cleanup of the federation control plane is not supported in `kubefed` yet.
For now, we must delete the `federation-system` namespace to remove all the federation resources.
This removes everything except the persistent storage volume that is dynamically provisioned for the
federation control plane's etcd. You can delete the federation namespace by running the
following command in the correct context:

```bash
kubectl delete ns federation-system --context=${HOST_CLUSTER}
```

#### Delete the federation context

```bash
kubectl config use-context ${HOST_CLUSTER}
kubectl config delete-context federation
```
