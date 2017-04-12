# Federated Kubernetes Tutorial

This tutorial will walk you through setting up a Kubernetes cluster federation using `kubefed`.

## Create the Kubernetes Clusters

Use the `gcloud container clusters create` command to create a Kubernetes cluster in the following zones:

- us-west1-b
- us-central1-b
- us-east1-b

Run each command separately to build the clusters in parallel.

#### gce-us-west1

```
gcloud container clusters create gce-us-west1 \
  --zone=us-west1-b \
  --scopes "cloud-platform,storage-ro,logging-write,monitoring-write,service-control,service-management,https://www.googleapis.com/auth/ndev.clouddns.readwrite"
```

#### gce-us-central1

```
gcloud container clusters create gce-us-central1 \
  --zone=us-central1-b \
  --scopes "cloud-platform,storage-ro,logging-write,monitoring-write,service-control,service-management,https://www.googleapis.com/auth/ndev.clouddns.readwrite"
```

#### gce-us-east1

```
gcloud container clusters create gce-us-east1 \
  --zone=us-east1-b \
  --scopes "cloud-platform,storage-ro,logging-write,monitoring-write,service-control,service-management,https://www.googleapis.com/auth/ndev.clouddns.readwrite"
```
#### Verify the clusters

At this point you should have 3 Kubernetes clusters running across 3 GCP regions.

```
gcloud container clusters list
```

#### Store the GCP Project Name

```
export GCP_PROJECT=$(gcloud config list --format='value(core.project)')
```

#### Download and Install kubefed and kubectl

Replace the version string with whatever version you want in the `curl` command below.

```
curl -O https://storage.googleapis.com/kubernetes-release/release/v1.5.5/kubernetes-client-linux-amd64.tar.gz
tar -xzvf kubernetes-client-linux-amd64.tar.gz kubernetes/client/bin/kubefed
tar -xzvf kubernetes-client-linux-amd64.tar.gz kubernetes/client/bin/kubectl
sudo cp kubernetes/client/bin/kubefed /usr/local/bin
sudo chmod +x /usr/local/bin/kubefed
sudo cp kubernetes/client/bin/kubectl /usr/local/bin
sudo chmod +x /usr/local/bin/kubectl
```

#### Configuring kubeconfig

The `gcloud container clusters create` command will configure `kubectl` with each of the contexts and grab the credentials for each cluster.

List the contexts stored in your local kubeconfig. These will be used later by the `kubefed` command.

```
kubectl config get-contexts --output=name
```

## Cluster DNS Managed Zone

Kubernetes federated services are able to manage external DNS entries based on services created across a federated set of Kubernetes clusters.
For this example, we'll setup a [Google DNS managed zone](https://cloud.google.com/dns/zones) to hold the DNS entries. Kubernetes supports
other external DNS providers using a plugin based system on the Federated Controller Manager.

#### Create a Google DNS Managed Zone

The follow command will create a DNS zone named `federation.com`. Specify your own zone name here. In a production setup a valid managed
zone backed by a registered DNS domain should be used.

```
gcloud dns managed-zones create federation \
  --description "Kubernetes federation testing" \
  --dns-name federation.com
```

## Initialize the Federated Control Plane

Initialization is easy with the `kubefed init` command. We will use the us-west region to host our federated control plane.
Replace the `--dns-zone-name` parameter to match the DNS zone name you just used above when you created the Google DNS Managed Zone.
Be sure to include the trailing `.`.

`kubefed init` will set some defaults if you do not override them on the command line.
For example, `--dns-provider='google-clouddns'` is set by default which is what we want anyway. Additionally,
you can pass`--image='gcr.io/google_containers/hyperkube-amd64:v1.5.5'` to specify a different version of the
federation API server and controller manager. By default, the image version it pulls will match the version of `kubefed` you
are using i.e. `v1.5.5` in this case.

```
kubefed init federation \
    --host-cluster-context=gke_${GCP_PROJECT}_us-west1-b_gce-us-west1 \
    --dns-zone-name=federation.com.
```

Once the command completes, you will have a federated API server and controller-manager running in the us-west zone, in addition
to a `federation` context for `kubectl` commands.

## Join the Kubernetes Clusters to the Federation

We'll use `kubefed join` to join each of the Kubernetes clusters in each zone. We need to specify in which context the federaton control plane
is running using the `--host-cluster-context` parameter as well as the context of the Kubernetes cluster we're joining to the federation using
the `--cluster-context` parameter.

#### Use federation context

Before proceeding, make sure we're using the newly created `federation` context to run our `kubefed join` commands.

```
kubectl config use-context federation
```

#### gce-us-west1

```
kubefed join gce-us-west1 \
    --host-cluster-context=gke_${GCP_PROJECT}_us-west1-b_gce-us-west1 \
    --cluster-context=gke_${GCP_PROJECT}_us-west1-b_gce-us-west1
```

#### gce-us-central1

```
kubefed join gce-us-central1 \
    --host-cluster-context=gke_${GCP_PROJECT}_us-west1-b_gce-us-west1 \
    --cluster-context=gke_${GCP_PROJECT}_us-central1-b_gce-us-central1
```

#### gce-us-east1

```
kubefed join gce-us-east1 \
    --host-cluster-context=gke_${GCP_PROJECT}_us-west1-b_gce-us-west1 \
    --cluster-context=gke_${GCP_PROJECT}_us-east1-b_gce-us-east1
```

#### Verify

```
kubectl get clusters -w
```

## Update KubeDNS

Lastly, now that the federated cluster is up and ready, we need to update kube-dns in each cluster to specify the federation domain name.
Unfortunately, this is a manual step that `kubefed` does not do for you yet until hopefully the Kubernetes 1.6 release. See Kubernetes issue #38400
and PR #39338 for more details.

To update the kube-dns we will add a config map to the kube-dns namespace in each cluster specifying the federation domain name.

#### Replace federation zone name

Before running the below command make sure to replace `federation.com` with the zone name you specified when creating the Google
DNS Managed Zone above.

```
sed 's/federation.com/YOUR_ZONE_NAME/' configmap/federation-cm.yaml > tmp \
    && mv -f tmp configmap/federation-cm.yaml
```

#### Create the Config Map

##### gce-us-west1

```
kubectl --context="gke_${GCP_PROJECT}_us-west1-b_gce-us-west1" \
  --namespace=kube-system \
  create -f configmap/federation-cm.yaml
```

```
kubectl --context="gke_${GCP_PROJECT}_us-west1-b_gce-us-west1" \
  --namespace=kube-system \
  get configmap kube-dns -o yaml
```

##### gce-us-central1

```
kubectl --context="gke_${GCP_PROJECT}_us-central1-b_gce-us-central1" \
  --namespace=kube-system \
  create -f configmap/federation-cm.yaml
```

```
kubectl --context="gke_${GCP_PROJECT}_us-central1-b_gce-us-central1" \
  --namespace=kube-system \
  get configmap kube-dns -o yaml
```

##### gce-us-east1

```
kubectl --context="gke_${GCP_PROJECT}_us-east1-b_gce-us-east1" \
  --namespace=kube-system \
  create -f configmap/federation-cm.yaml
```

```
kubectl --context="gke_${GCP_PROJECT}_us-east1-b_gce-us-east1" \
  --namespace=kube-system \
  get configmap kube-dns -o yaml
```

You should now have a working federated Kubernetes cluster spanning the west, central, and east zones.

## Cleanup

Cleanup is basically some of the setup steps in reverse.

#### Unjoin clusters

##### gce-us-west1

```
kubefed unjoin gce-us-west1 \
    --host-cluster-context=gke_${GCP_PROJECT}_us-west1-b_gce-us-west1
```

##### gce-us-central1

```
kubefed unjoin gce-us-central1 \
    --host-cluster-context=gke_${GCP_PROJECT}_us-west1-b_gce-us-west1
```

##### gce-us-east1

```
kubefed unjoin gce-us-east1 \
    --host-cluster-context=gke_${GCP_PROJECT}_us-west1-b_gce-us-west1
```

#### Delete federation control plane

Cleanup of the federation control plane is not supported in `kubefed` yet.
For now, we must delete the `federation-system` namespace to remove all the federation resources.
This removes everything except the persistent storage volume that is dynamically provisioned for the
federation control plane's etcd. You can delete the federation namespace by running the
following command in the correct context:

```
kubectl delete ns federation-system --context=gke_${GCP_PROJECT}_us-west1-b_gce-us-west1
```

#### Delete the federation context

```
kubectl config use-context gke_${GCP_PROJECT}_us-west1-b_gce-us-west1
kubectl config delete-context federation
```

#### Delete Google DNS Managed Zone

The managed zone must be empty before you can delete it. Visit the Cloud DNS console
and delete all resource records before running the following command:

```
gcloud dns managed-zones delete federation
```

#### Delete Kubernetes clusters

Delete the 3 GKE clusters. Run each command separately to delete the clusters in parallel.

```
gcloud container clusters delete gce-us-west1 --zone=us-west1-b
gcloud container clusters delete gce-us-central1 --zone=us-central1-b
gcloud container clusters delete gce-us-east1 --zone=us-east1-b
```
