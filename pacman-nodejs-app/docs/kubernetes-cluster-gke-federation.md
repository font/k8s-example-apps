# Federated Kubernetes Tutorial

This tutorial will walk you through setting up a Kubernetes cluster federation
using [Federation-v2](https://github.com/kubernetes-sigs/federation-v2) and
[`kubefnord`](https://github.com/kubernetes-sigs/federation-v2/tree/master/cmd/kubefnord).

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
  --zone=us-west1-b \
  --scopes "cloud-platform,storage-ro,logging-write,monitoring-write,service-control,service-management,https://www.googleapis.com/auth/ndev.clouddns.readwrite"
```

#### gke-us-central1

```bash
gcloud container clusters create gke-us-central1 \
  --zone=us-central1-b \
  --scopes "cloud-platform,storage-ro,logging-write,monitoring-write,service-control,service-management,https://www.googleapis.com/auth/ndev.clouddns.readwrite"
```

#### gke-us-east1

```bash
gcloud container clusters create gke-us-east1 \
  --zone=us-east1-b \
  --scopes "cloud-platform,storage-ro,logging-write,monitoring-write,service-control,service-management,https://www.googleapis.com/auth/ndev.clouddns.readwrite"
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

## Cluster DNS Managed Zone

<!--TODO: update with instructions once available-->
<!--Kubernetes federated services are able to manage external DNS entries based on services created across a federated set of Kubernetes clusters.-->
For this example, we'll setup a [Google DNS managed
zone](https://cloud.google.com/dns/zones) to hold the DNS entries. <!--Kubernetes supports
other external DNS providers using a plugin based system on the Federated
Controller Manager.-->

#### Create a Google DNS Managed Zone

The follow command will create a DNS zone named `federation.com`. Specify your own zone name here. In a production setup a valid managed
zone backed by a registered DNS domain should be used.

```bash
gcloud dns managed-zones create federation \
  --description "Kubernetes federation testing" \
  --dns-name federation.com
```

## Download and Install kubectl and kubefnord

Replace the version string with whatever version you want in the `curl` command below.

```bash
curl -O https://storage.googleapis.com/kubernetes-release/release/v1.10.1/kubernetes-client-linux-amd64.tar.gz
tar -xzvf kubernetes-client-linux-amd64.tar.gz kubernetes/client/bin/kubectl
sudo cp kubernetes/client/bin/kubectl /usr/local/bin
sudo chmod +x /usr/local/bin/kubectl
```

<!--TODO: update with binary path download once available-->
```bash
go get github.com/kubernetes-sigs/federation-v2
cd ${GOPATH}/src/github.com/kubernetes-sigs/federation-v2
go build -o bin/kubefnord cmd/kubefnord/kubefnord.go
sudo mv bin/kubefnord /usr/local/bin/
```

#### Configuring kubectl

The `gcloud container clusters create` command will configure `kubectl` with each of the contexts and grab the credentials for each cluster.

List the contexts stored in your local kubeconfig. These will be used later by
the `kubefnord` command.

```bash
kubectl config get-contexts --output=name
```

Let's first rename the contexts to make them easier to deal with:

```bash
kubectl config rename-context gke_${GCP_PROJECT}_us-west1-b_gke-us-west1 gke-us-west1
kubectl config rename-context gke_${GCP_PROJECT}_us-central1-b_gke-us-central1 gke-us-central1
kubectl config rename-context gke_${GCP_PROJECT}_us-east1-b_gke-us-east1 gke-us-east1
```

## Deploy the Cluster Registry

```bash
crinit aggregated init mycr --host-cluster-context=gke-us-west1
```

## Initialize the Federated-v2 Control Plane

Initialization is easy with the `apiserver-boot` command. The command must be
run from the root of the federation-v2 repo. We will use the us-west region to
host our federated control plane.
<!--TODO: update with DNS instructions once available.
Replace the `--dns-zone-name` parameter to match the DNS zone name you just used above when you created the Google DNS Managed Zone.
**Be sure to include the trailing `.` in the DNS zone name**.
-->

<!--TODO
`apiserver-boot` will set some defaults if you do not override them on the command line.
For example, you can pass `--image` to specify a different version of the federation API server and controller manager.
By default, the image version it pulls will match the version of `kubefnord` you are
using i.e. `v1.6.4` in this case.
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
kubectl config use-context gke-us-west1

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

Adjust memory limit for apiserver, controller, and etcd:

```bash
kubectl -n federation patch deploy federation -p \
    '{"spec":{"template":{"spec":{"containers":[{"name":"apiserver","resources":{"limits":{"memory":"128Mi"},"requests":{"memory":"64Mi"}}}]}}}}'
kubectl -n federation patch deploy federation -p \
    '{"spec":{"template":{"spec":{"containers":[{"name":"controller","resources":{"limits":{"memory":"128Mi"},"requests":{"memory":"64Mi"}}}]}}}}'
kubectl -n federation patch statefulset etcd -p \
    '{"spec":{"template":{"spec":{"containers":[{"name":"etcd","resources":{"limits":{"memory":"128Mi"},"requests":{"memory":"64Mi"}}}]}}}}'
```


Once the command completes, you will have a federated API server and
controller-manager running in the us-west zone.

## Join the Kubernetes Clusters to the Federation

We'll use `kubefnord join` to join each of the Kubernetes clusters in each
zone. We need to specify in which context the federaton control plane is
running using the `--host-cluster-context` parameter as well as the context of
the Kubernetes cluster we're joining to the federation using the
`--cluster-context` parameter, or leave that option blank if it matches the
cluster name specified.

For GCP, if you're using RBAC permissions then you'll need to grant your user
the ability to create authorization roles by running the following Kubernetes
command:

```bash
export GCP_ZONES="west central east"
for i in ${GCP_ZONES}; do \
    kubectl --context=gke-us-${i}1 create clusterrolebinding cluster-admin-binding \
    --clusterrole cluster-admin --user $(gcloud config get-value account)
done
```

#### gke-us-west1

```bash
kubefnord join gke-us-west1 \
    --host-cluster-context=gke-us-west1 \
    --cluster-context=gke-us-west1 \
    --add-to-registry --v=2
```

#### gke-us-central1

```bash
kubefnord join gke-us-central1 \
    --host-cluster-context=gke-us-west1 \
    --cluster-context=gke-us-central1 \
    --add-to-registry --v=2
```

#### gke-us-east1

```bash
kubefnord join gke-us-east1 \
    --host-cluster-context=gke-us-west1 \
    --cluster-context=gke-us-east1 \
    --add-to-registry --v=2
```

#### Verify

```bash
kubectl get clusters
```

You should now have a working federated Kubernetes cluster spanning the west, central, and east zones.

## Cleanup

Cleanup is basically some of the setup steps in reverse.

#### Unjoin clusters

Unjoining the clusters from the federation is not currently supported in
`kubefnord` yet. For now, you can manually run the following commands using an
`unjoin.sh` script in this repo:

##### gke-us-west1

```bash
./tools/unjoin/unjoin.sh gke-us-west1 gke-us-west1

```

##### gke-us-central1

```bash
./tools/unjoin/unjoin.sh gke-us-west1 gke-us-central1
```

##### gke-us-east1

```bash
./tools/unjoin/unjoin.sh gke-us-west1 gke-us-east1
```

#### Delete the Cluster Registry

```bash
crinit aggregated delete mycr --host-cluster-context=gke-us-west1
```

#### Delete federation control plane

Cleanup of the federation control plane is not supported in `kubefnord` yet.
For now, we must delete the `federation` namespace to remove all the federation
resources.  You can delete the federation namespace by running the following
command in the correct context:

```bash
kubectl delete ns federation --context=gke-us-west1
```

#### Delete Google DNS Managed Zone

The managed zone must be empty before you can delete it. Visit the Cloud DNS console
and delete all resource records before running the following command:

```bash
gcloud dns managed-zones delete federation
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
for i in ${GCP_ZONES}; do \
    kubectl config delete-context gke-us-${i}1
done
```
