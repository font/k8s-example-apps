# Federated Kubernetes Tutorial

This tutorial will walk you through setting up a Kubernetes cluster federation
using `kubefed2` with multiple public cloud providers.

## Prerequisites

#### Kubernetes Clusters Created

The Kubernetes clusters that you plan to use to create the federation should already be created. If not, please
follow steps to create them using [GKE](kubernetes-cluster-gke-federation.md), [AWS](kubernetes-cluster-aws.md),
and [Azure](kubernetes-cluster-azure.md).

#### Cluster DNS Managed Zone Created

You should already have a Kubernetes cluster DNS Managed Zone. See
[these instructions for an example of creating one with Google Cloud DNS](kubernetes-cluster-gke-federation.md#cluster-dns-managed-zone).

#### kubectl and kubefed2 installed

The `kubectl` and `kubefed2` commands should already be installed. You should
match the version of `kubectl` to the version of Kubernetes
your clusters are running.

```bash
kubectl version
```

#### kubectl configured

The `kubectl` command should already have access to the kubeconfig or contexts for each cluster you're going to add to the federation.

To verify, list the contexts stored in your kubeconfig. These will be used
later by the `kubefed2` command.

```bash
kubectl config get-contexts --output=name
```

#### Store the GCP Project Name

If you're planning to use at least 1 GKE cluster, you'll want to save your project ID in a handy variable:

```bash
export GCP_PROJECT=$(gcloud config list --format='value(core.project)')
```

#### Rename Cluster Contexts

We'll want to rename the cluster contexts to make it simpler throughout our
setup.

```bash
kubectl config rename-context gke_${GCP_PROJECT}_us-west1-b_gke-us-west1 gke-us-west1
kubectl config rename-context ${AWS_CLUSTER_NAME} aws-us-east1
```

## Configure Kubernetes Federation Host Cluster

Out of the lists of contexts available to `kubectl` from the command above, select the context you want to use to host the Kubernetes
federation control plane. For example, using a GKE cluster in the us-west region:

```bash
HOST_CLUSTER=gke-us-west1
kubectl config use-context ${HOST_CLUSTER}
```

## Configure Kubernetes Federation Clusters to Join

Out of the lists of contexts available to `kubectl` from the command above, select the contexts you want to join to the Kubernetes
federation. For example, using the GKE host cluster in the us-west region, an Azure cluster in the us-central region, and an AWS cluster
in the us-east region with their corresponding context names:

```bash
JOIN_CLUSTERS="${HOST_CLUSTER} az-us-central1 aws-us-east1"
```

## Deploy the Federated-v2 Control Plane and Join the Clusters to the Federation

Initialization is a matter of adding the appropriate RBAC permissions
controller, creating namespaces and applying a couple of YAML configs. All of
this is automated by the `deploy-federation.sh` script. We will
use the `HOST_CLUSTER` context to host our federated control plane. The script also
uses `kubefed2 join` to join each of the Kubernetes clusters in each zone.

For GCP, if you're using RBAC permissions then you'll need to grant your user
the ability to create authorization roles by running the following Kubernetes
command:

```bash
kubectl --context=${HOST_CLUSTER} create clusterrolebinding cluster-admin-binding \
    --clusterrole cluster-admin --user $(gcloud config get-value account)
```

Clone the `federation-v2` repo:

```bash
mkdir -p go/src/github.com/kubernetes-sigs
export GOPATH="$(pwd)/go"
cd go/src/github.com/kubernetes-sigs
git clone https://github.com/kubernetes-sigs/federation-v2.git
cd federation-v2
```

Then run the script to automate deployment and joining. The script takes care of
automatically joining the `HOST_CLUSTER` `gke-us-west` so we'll just pass the
other 2 cluster contexts.

```bash
./scripts/deploy-federation-latest.sh az-us-central1 aws-us-east1
```

Once the command completes, you will have a working federation of all 3
clusters with push reconcilation for the supported types.

#### Verify

```bash
kubectl -n kube-multicluster-public describe clusters
kubectl -n federation-system describe federatedclusters
```

If you see each cluster with an `OK` status, then you now have a working
federation of Kubernetes clusters spanning the west, central, and east zones
across all 3 public cloud providers.

## Join the Kubernetes Clusters to the Federation (Manually)

**NOTE:** The clusters should already be joined to the federation after the
above steps so this section is here in case you want to join the clusters
manually for whatever reason.

We'll use `kubefed2 join` to join each of the Kubernetes clusters. We need to
specify in which context the federaton control plane is running using the
`--host-cluster-context` parameter as well as the context of the Kubernetes
cluster we're joining to the federation using the `--cluster-context`
parameter, or leave that option blank if it matches the cluster name specified.

For GCP, if you're using RBAC permissions then you'll need to grant your user
the ability to create authorization roles by running the following Kubernetes
command:

```bash
kubectl --context=${HOST_CLUSTER} create clusterrolebinding cluster-admin-binding \
    --clusterrole cluster-admin --user $(gcloud config get-value account)
```

#### Join Clusters

If you want to join each cluster individually such as if their context and cluster names did not match, then join each one like so:

##### gke-us-west1

```bash
kubefed2 join gke-us-west1 \
    --host-cluster-context=${HOST_CLUSTER} \
    --cluster-context=${HOST_CLUSTER} \
    --add-to-registry --v=2
```

##### az-us-central1

```bash
kubefed2 join az-us-central1 \
    --host-cluster-context=${HOST_CLUSTER} \
    --cluster-context=az-us-central1 \
    --add-to-registry --v=2
```

##### aws-us-east1

```bash
kubefed2 join aws-us-east1 \
    --host-cluster-context=${HOST_CLUSTER} \
    --cluster-context=aws-us-east1 \
    --add-to-registry --v=2
```

Otherwise, if both cluster and context names match, then you can join them all
using a loop:

```bash
for c in ${JOIN_CLUSTERS}; do
    kubefed2 join ${c} \
        --host-cluster-context=${HOST_CLUSTER} \
        --cluster-context=${c} \
        --add-to-registry --v=2
done
```

#### Verify

```bash
kubectl -n kube-multicluster-public get clusters
kubectl -n federation-system describe federatedclusters
```

You should now have a working federated Kubernetes cluster spanning each zone.

## Cleanup

Cleanup is basically some of the setup steps in reverse.

#### Unjoin Individual Clusters

Unjoining the clusters from the federation is easy by using the `kubefed2
unjoin` command.

If you joined each cluster individually by providing a unique name to each, then unjoin each one like so:

##### gke-us-west1

```bash
kubefed2 unjoin ${HOST_CLUSTER} --host-cluster-context ${HOST_CLUSTER} \
    --remove-from-registry --v=2
```

##### az-us-central1

```bash
kubefed2 unjoin az-us-central1 --host-cluster-context ${HOST_CLUSTER} \
    --remove-from-registry --v=2
```

##### aws-us-east1

```bash
kubefed2 unjoin aws-us-east1 --host-cluster-context ${HOST_CLUSTER} \
    --remove-from-registry --v=2
```

Otherwise unjoin them all in one fell swoop:

```bash
for c in ${JOIN_CLUSTERS}; do
    kubefed2 unjoin ${c} --host-cluster-context ${HOST_CLUSTER} \
        --remove-from-registry --v=2
done
```

#### Delete federation control plane

You can delete the federation deployment by running the following script:

```bash
./scripts/delete-federation.sh
```
