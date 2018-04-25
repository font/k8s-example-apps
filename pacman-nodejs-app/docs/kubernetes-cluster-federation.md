# Federated Kubernetes Tutorial

This tutorial will walk you through setting up a Kubernetes cluster federation
using `kubefnord` with multiple public cloud providers.

## Prerequisites

#### Kubernetes Clusters Created

The Kubernetes clusters that you plan to use to create the federation should already be created. If not, please
follow steps to create them using [GKE](kubernetes-cluster-gke-federation.md), [AWS](kubernetes-cluster-aws.md),
and [Azure](kubernetes-cluster-azure.md).

#### Cluster DNS Managed Zone Created

You should already have a Kubernetes cluster DNS Managed Zone. See
[these instructions for an example of creating one with Google Cloud DNS](kubernetes-cluster-gke-federation.md#cluster-dns-managed-zone).

#### kubectl and kubefnord installed

The `kubectl` and `kubefnord` commands should already be installed. You should
match the version of `kubectl` to the version of Kubernetes
your clusters are running.

```bash
kubectl version
```

#### kubectl configured

The `kubectl` command should already have access to the kubeconfig or contexts for each cluster you're going to add to the federation.

To verify, list the contexts stored in your kubeconfig. These will be used
later by the `kubefnord` command.

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

## Deploy the Cluster Registry

```bash
crinit aggregated init mycr --host-cluster-context=${HOST_CLUSTER}
```

## Initialize the Federated-v2 Control Plane

Initialization is easy with the `apiserver-boot` command. The command must be
run from the root of the federation-v2 repo. We will use the `HOST_CLUSTER`
context to host our federated control plane.
<!--TODO: update with DNS instructions once available.
Replace the `--dns-zone-name` parameter to match the DNS zone name you used when you created your DNS zone.
**Be sure to include the trailing `.` in the DNS zone name**.
-->

<!--TODO
`apiserver-boot` will set some defaults if you do not override them on the command line.
For example, you can pass `--image` to specify a different version of the
federation API server and controller manager. By default, the image version it pulls will
match the version of `kubefnord` you are using.
-->

<!--
```bash
# Restrictive API server permissions
kubectl create rolebinding -n kube-system \
    federation.k8s.io:extension-apiserver-authentication-reader \
    --role=extension-apiserver-authentication-reader \
    --serviceaccount=federation:default

kubectl create clusterrolebinding federation.k8s.io:apiserver-auth-delegator \
    --clusterrole=system:auth-delegator \
    --serviceaccount=federation:default
```
-->

```bash
kubectl create namespace federation

apiserver-boot run in-cluster --name federation --namespace federation \
    --image gcr.io/<username>/federation-v2:<tagname> \
    --controller-args="-logtostderr,-v=4"

# This is a bit permissive, we need to create a clusterrole for the federation
# objects and provide the necessary VERB permissions to them for the controller
# manager to use via a cluster role binding.
kubectl create clusterrolebinding federation-admin \
    --clusterrole=cluster-admin --serviceaccount=federation:default
```

Adjust memory limit for apiserver:

```bash
kubectl -n federation patch deploy federation -p \
    '{"spec":{"template":{"spec":{"containers":[{"name":"apiserver","resources":{"limits":{"memory":"128Mi"},"requests":{"memory":"64Mi"}}}]}}}}'
```

Once the command completes, you will have a federated API server and
controller-manager running in the `HOST_CLUSTER` zone.

## Join the Kubernetes Clusters to the Federation

We'll use `kubefnord join` to join each of the Kubernetes clusters. We need to
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
kubefnord join gke-us-west1 \
    --host-cluster-context=${HOST_CLUSTER} \
    --cluster-context=${HOST_CLUSTER} \
    --add-to-registry --v=2
```

##### az-us-central1

```bash
kubefnord join az-us-central1 \
    --host-cluster-context=${HOST_CLUSTER} \
    --cluster-context=az-us-central1 \
    --add-to-registry --v=2
```

##### aws-us-east1

```bash
kubefnord join aws-us-east1 \
    --host-cluster-context=${HOST_CLUSTER} \
    --cluster-context=aws-us-east1 \
    --add-to-registry --v=2
```

Otherwise, if both cluster and context names match, then you can join them all
using a loop:

```bash
for c in ${JOIN_CLUSTERS}; do
    kubefnord join ${c} \
        --host-cluster-context=${HOST_CLUSTER} \
        --cluster-context=${c} \
        --add-to-registry --v=2
done
```

#### Verify

```bash
kubectl get clusters
```

You should now have a working federated Kubernetes cluster spanning each zone.

## Cleanup

Cleanup is basically some of the setup steps in reverse.

#### Unjoin Individual Clusters

Unjoining the clusters from the federation is not currently supported in
`kubefnord` yet. For now, you can manually run the following commands using an
`unjoin.sh` script in this repo.

If you joined each cluster individually by providing a unique name to each, then unjoin each one like so:

##### gke-us-west1

```bash
./tools/unjoin/unjoin.sh ${HOST_CLUSTER} ${HOST_CLUSTER}
```

##### az-us-central1

```bash
./tools/unjoin/unjoin.sh ${HOST_CLUSTER} az-us-central1
```

##### aws-us-east1

```bash
./tools/unjoin/unjoin.sh ${HOST_CLUSTER} aws-us-east1
```

Otherwise unjoin them all in one fell swoop:

```bash
for c in ${JOIN_CLUSTERS}; do
    ./tools/unjoin/unjoin.sh ${HOST_CLUSTER} ${c}
done
```

#### Delete the Cluster Registry

```bash
crinit aggregated delete mycr --host-cluster-context=${HOST_CLUSTER}
```

#### Delete federation control plane

Cleanup of the federation control plane is not supported in `kubefnord` yet.
For now, we must delete the `federation` namespace to remove all the federation
resources.  You can delete the federation namespace by running the following
command in the correct context:

```bash
kubectl delete ns federation --context=${HOST_CLUSTER}
```
