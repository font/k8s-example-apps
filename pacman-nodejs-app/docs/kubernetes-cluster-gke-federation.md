# Federated Kubernetes Tutorial

This tutorial will walk you through setting up a Kubernetes cluster federation
using [Federation-v2](https://github.com/kubernetes-sigs/federation-v2) and
[`kubefed2`](https://github.com/kubernetes-sigs/federation-v2/tree/master/cmd/kubefed2)
on GKE.

## Install Google Cloud SDK

To test on a Kubernetes cluster, make sure you have the [Google Cloud SDK
installed](https://cloud.google.com/sdk/). You can quickly do this on Linux/Mac
with:

```
curl https://sdk.cloud.google.com | bash
```

Once installed, log in and update it:

```
gcloud auth login
gcloud components update
```

## Create the Kubernetes Clusters

Use the `gcloud container clusters create` command to create a Kubernetes cluster in the following zones:

- us-west1-b
- us-central1-b
- us-east1-b

Run each command separately to build the clusters in parallel.

If you're looking to deploy a specific version of Kubernetes other than the
current default supported by Google Cloud Platform, GCP supports the
`--cluster-version` option as part of the `gcloud container clusters create`
command.  For example, if you'd like to deploy Kubernetes version 1.9.6, then
pass in `--cluster-version=1.9.6-gke.1`. See [Google's Container Engine Release
Notes](https://cloud.google.com/container-engine/release-notes) for supported
versions of Kubernetes.

#### gke-us-west1

```bash
gcloud container clusters create gke-us-west1 \
  --zone=us-west1-b --scopes "cloud-platform"
```

#### gke-us-central1

```bash
gcloud container clusters create gke-us-central1 \
  --zone=us-central1-b --scopes "cloud-platform"
```

#### gke-us-east1

```bash
gcloud container clusters create gke-us-east1 \
  --zone=us-east1-b --scopes "cloud-platform"
```
#### Verify the clusters

At this point you should have 3 Kubernetes clusters running across 3 GCP regions.

```bash
gcloud container clusters list
```

#### Store the GCP Project Name

```bash
export GCP_PROJECT=$(gcloud config list --format='value(core.project)')
```

## Download and Install kubectl and kubefed2

Replace the version strings with whatever version you want in the `curl`
commands below.

```bash
curl -O https://storage.googleapis.com/kubernetes-release/release/v1.10.1/kubernetes-client-linux-amd64.tar.gz
tar -xzvf kubernetes-client-linux-amd64.tar.gz kubernetes/client/bin/kubectl
sudo mv kubernetes/client/bin/kubectl /usr/local/bin
sudo chmod +x /usr/local/bin/kubectl
```

<!--TODO: update with binary path download once available-->
```bash
curl -LO https://github.com/kubernetes-sigs/federation-v2/releases/download/v0.0.2/kubefed2.tar.gz
tar -xvzf kubefed2.tar.gz 
sudo mv kubefed2 /usr/local/bin
```

#### Configuring kubectl

The `gcloud container clusters create` command will configure `kubectl` with each of the contexts and grab the credentials for each cluster.

List the contexts stored in your local kubeconfig. These will be used later by
the `kubefed2` command.

```bash
kubectl config get-contexts --output=name
```

Let's first rename the contexts to make them easier to deal with:

```bash
kubectl config rename-context gke_${GCP_PROJECT}_us-west1-b_gke-us-west1 gke-us-west1
kubectl config rename-context gke_${GCP_PROJECT}_us-central1-b_gke-us-central1 gke-us-central1
kubectl config rename-context gke_${GCP_PROJECT}_us-east1-b_gke-us-east1 gke-us-east1
```

## Deploy the Federated-v2 Control Plane and Join the Clusters to the Federation

Initialization is a matter of adding the appropriate RBAC permissions
controller, creating namespaces and applying a couple of YAML configs. All of
this is automated by the `deploy-federation.sh` script. We will
use the us-west region to host our federated control plane. The script also
uses `kubefed2 join` to join each of the Kubernetes clusters in each zone.

```bash
kubectl config use-context gke-us-west1
```

For GCP, if you're using RBAC permissions then you'll need to grant your user
the ability to create authorization roles by running the following Kubernetes
command:

```bash
export CLUSTERS="gke-us-west1 gke-us-central1 gke-us-east1"
for i in ${CLUSTERS}; do \
    kubectl --context=${i} create clusterrolebinding cluster-admin-binding \
    --clusterrole cluster-admin --user $(gcloud config get-value account)
done
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
automatically joining the host cluster `gke-us-west1` so we'll just pass the
other 2 cluster contexts.

```bash
./scripts/deploy-federation-latest.sh gke-us-central1 gke-us-east1
```

Once the command completes, you will have a working federation of all 3
clusters with push reconcilation for the supported types.

#### Verify

```bash
kubectl -n kube-multicluster-public describe clusters
kubectl -n federation-system describe federatedclusters
```

If you see each cluster with an `OK` status, then you now have a working
federation of Kubernetes clusters spanning the west, central, and east zones.

## Join the Kubernetes Clusters to the Federation (Manually)

**NOTE:** The clusters should already be joined to the federation after the
above steps so this section is here in case you want to join the clusters
manually for whatever reason.

We'll use `kubefed2 join` to join each of the Kubernetes clusters in each
zone. We need to specify in which context the federaton control plane is
running using the `--host-cluster-context` parameter as well as the context of
the Kubernetes cluster we're joining to the federation using the
`--cluster-context` parameter, or leave that option blank if it matches the
cluster name specified.

For GCP, if you're using RBAC permissions then you'll need to grant your user
the ability to create authorization roles by running the following Kubernetes
command:

```bash
for i in ${CLUSTERS}; do \
    kubectl --context=${i} create clusterrolebinding cluster-admin-binding \
    --clusterrole cluster-admin --user $(gcloud config get-value account)
done
```

#### gke-us-west1

```bash
kubefed2 join gke-us-west1 \
    --host-cluster-context=gke-us-west1 \
    --cluster-context=gke-us-west1 \
    --add-to-registry --v=2
```

#### gke-us-central1

```bash
kubefed2 join gke-us-central1 \
    --host-cluster-context=gke-us-west1 \
    --cluster-context=gke-us-central1 \
    --add-to-registry --v=2
```

#### gke-us-east1

```bash
kubefed2 join gke-us-east1 \
    --host-cluster-context=gke-us-west1 \
    --cluster-context=gke-us-east1 \
    --add-to-registry --v=2
```

#### Verify

```bash
kubectl -n kube-multicluster-public describe clusters
kubectl -n federation-system describe federatedclusters
```

If you see each cluster with an `OK` status, then you now have a working
federation of Kubernetes clusters spanning the west, central, and east zones.

## Cleanup

Cleanup is basically some of the setup steps in reverse.

#### Unjoin clusters

Unjoining the clusters from the federation is easy by using the `kubefed2
unjoin` command:

##### gke-us-west1

```bash
kubefed2 unjoin gke-us-west1 --host-cluster-context gke-us-west1 --remove-from-registry --v=2
```

##### gke-us-central1

```bash
kubefed2 unjoin gke-us-central1 --host-cluster-context gke-us-west1 --remove-from-registry --v=2
```

##### gke-us-east1

```bash
kubefed2 unjoin gke-us-east1 --host-cluster-context gke-us-west1 --remove-from-registry --v=2
```

#### Delete federation control plane

You can delete the federation deployment by running the following script:

```bash
./scripts/delete-federation.sh
```

#### Delete Kubernetes clusters

Delete the 3 GKE clusters. Run each command separately to delete the clusters in parallel.

```bash
gcloud container clusters delete gke-us-west1 --zone=us-west1-b
gcloud container clusters delete gke-us-central1 --zone=us-central1-b
gcloud container clusters delete gke-us-east1 --zone=us-east1-b
```

#### Delete the kubeconfig contexts

```bash
for i in ${CLUSTERS}; do \
    kubectl config delete-context gke-us-${i}1
done
```
