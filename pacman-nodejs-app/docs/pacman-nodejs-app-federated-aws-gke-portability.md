# Pac-Man Application On Federated Kubernetes Cluster With Public Cloud Provider Portability

This guide will walk you through creating multiple Kubernetes clusters spanning
multiple public cloud providers and use a federation control plane to deploy
the Pac-Man Node.js application onto AWS and GKE clusters, then move it just to
GKE.

## High-Level Architecture

Below is a diagram demonstrating the architecture of the game across the federated kubernetes cluster after all the steps are completed.

![Pac-Man Game Architecture](images/Kubernetes-Federation-Game-AWS-GKE-Portability.png)

## Prerequisites

#### Clone the repository

Follow these steps to [clone the repository](../README.md#clone-this-repository).

#### Create the Pac-Man Container Image

Follow these steps to [create the Pac-Man application container image](../README.md#create-application-container-image).

#### Set up Google Cloud SDK and Push Container Image

Follow these steps to [push the Pac-Man container image to your Google Cloud Container Registry](../README.md#kubernetes-components).

#### Make Container Image Publicly Available

Follow [these steps in Google Cloud Platform's documentation](https://cloud.google.com/container-registry/docs/access-control#making_the_images_in_your_registry_publicly_available)
for making your container images in your registry publicly available. This will allow you to build and push the container
image to one place and allow all your Kubernetes clusters to download it from the same location. You could do this
similarly with the official Docker Hub.

#### Store the GCP Project Name

```bash
export GCP_PROJECT=$(gcloud config list --format='value(core.project)')
```

#### Create the Federated Kubernetes Clusters

For this part, note that you'll generally want to use a consistent version of Kubernetes when deploying in all of the different
public cloud providers e.g. GCP, AWS, and Azure. Each of the public cloud provider setup guides explain how to do this in more detail.

Follow these steps:

1. [Create 1 GKE Kubernetes clusters in 1 region i.e. us-west](kubernetes-cluster-gke-federation.md#gce-us-west1)
2. [Verify the GKE cluster](kubernetes-cluster-gke-federation.md#verify-the-clusters)
3. [Create Google DNS managed zone for cluster](kubernetes-cluster-gke-federation.md#cluster-dns-managed-zone)
4. [Download and install kubefed and kubectl](kubernetes-cluster-gke-federation.md#download-and-install-kubefed-and-kubectl)
5. [Create and verify 1 AWS Kubernetes cluster in 1 region i.e. us-east](kubernetes-cluster-aws.md)
6. [Using `kubefed` set up a Kubernetes federation containing each of these clusters: GKE and AWS](kubernetes-cluster-federation.md)

#### Export the Cluster Contexts

Using the list of contexts for `kubectl`:

```bash
kubectl config get-contexts --output=name
```

Determine which are the contexts in your federation that you want to deploy to and assign them to a variable:

```bash
export KUBE_FED_CLUSTERS="gke_${GCP_PROJECT}_us-west1-b_gce-us-west1 us-east-1.subdomain.example.com"
```

## Create MongoDB Resources

#### Create MongoDB Persistent Volume Claims

Now using the default storage class in each cluster, we'll create the PVC:

```bash
for i in ${KUBE_FED_CLUSTERS}; do
    kubectl --context=${i} \
        create -f persistentvolumeclaim/mongo-pvc.yaml
done
```

Verify the PVCs are bound in each clusters:

```bash
for i in ${KUBE_FED_CLUSTERS}; do
    kubectl --context=${i} \
        get pvc mongo-storage
done
```

#### Create MongoDB Service

This component creates the necessary mongo federation DNS entries for each cluster. The application uses `mongo` as
the host it connects to instead of `localhost`. Using `mongo` in each application will resolve to the local `mongo` instance
that's closest to the application in the cluster.

```bash
kubectl create -f services/mongo-service.yaml
```

Wait until the mongo service has all the external IP addresses (dynamic DNS for AWS) listed:

```bash
kubectl get svc mongo -o wide --watch
```

#### Create MongoDB Kubernetes Deployment

Now create the MongoDB Deployment that will use the `mongo-storage` persistent volume claim to mount the
directory that is to contain the MongoDB database files. In addition, we will pass the `--replSet rs0` parameter
to `mongod` in order to create a MongoDB replica set.

```
kubectl create -f deployments/mongo-deployment-rs.yaml
```

Scale the mongo deployment

```
kubectl scale deploy/mongo --replicas=2
```

Wait until the mongo deployment shows 2 pods available

```
kubectl get deploy mongo -o wide --watch
```

#### Create the MongoDB Replication Set

We'll have to bootstrap the MongoDB instances to create the replication set. For this,
we need to run the following commands on the MongoDB instance you want to designate as the primary (master). For our example,
let's use the GKE us-west1-b instance:

```bash
MONGO_POD=$(kubectl --context=gke_${GCP_PROJECT}_us-west1-b_gce-us-west1 get pod \
    --selector="name=mongo" \
    --output=jsonpath='{.items..metadata.name}')
kubectl --context=gke_${GCP_PROJECT}_us-west1-b_gce-us-west1 exec -it ${MONGO_POD} -- bash
```

Once inside this pod, make sure all Mongo DNS entries for each region are resolvable. Otherwise the command to
initialize the Mongo replica set below will fail. You can do this by installing DNS utilities such as `dig` and `nslookup` using:

```bash
apt-get update
apt-get -y install dnsutils
```

Then use either `dig` or `nslookup` to perform the following lookups for each zone:

```bash
dig mongo.default.federation.svc.us-west1.federation.com +noall +answer
nslookup mongo.default.federation.svc.us-west1.federation.com

dig mongo.default.federation.svc.us-east-1.federation.com +noall +answer
nslookup mongo.default.federation.svc.us-east-1.federation.com
```

Or check to make sure the load balancer DNS A record contains an IP address for each zone:

```bash
dig mongo.default.federation.svc.federation.com +noall +answer
nslookup mongo.default.federation.svc.federation.com
```

Once the DNS entries are resolvable, launch the `mongo` CLI:

```bash
mongo
```

Now we'll create an initial configuration specifying the one mongo in our replication set. In our example,
we'll use the GKE west and AWS east instances. Make sure to replace `federation.com` with the DNS zone name you created.

```
initcfg = {
        "_id" : "rs0",
        "members" : [
                {
                        "_id" : 0,
                        "host" : "mongo.default.federation.svc.us-west1.federation.com:27017"
                },
                {
                        "_id" : 1,
                        "host" : "mongo.default.federation.svc.us-east-1.federation.com:27017"
                }
        ]
}
```

Initiate the MongoDB replication set:

```
rs.initiate(initcfg)
```

Check the status until this instance shows as `PRIMARY`:

```
rs.status()
```

Once you have all instances showing up as `SECONDARY` and this one as `PRIMARY`, you have a working MongoDB replica set
that will replicate data across the clusters.

Go ahead and exit out of the Mongo CLI and out of the Pod.

## Create Pac-Man Resources

#### Create the Pac-Man Service

This component creates the necessary `pacman` federation DNS entries for each cluster. There will be A DNS entries created for each zone, region,
as well as a top level DNS A entry that will resolve to all zones for load balancing.

```bash
kubectl create -f services/pacman-service.yaml
```

Wait and verify the service has all the external IP addresses (dynamic DNS for AWS) listed:

```bash
kubectl get svc pacman -o wide --watch
```

#### Create the Pac-Man Deployment

We'll need to create the Pac-Man game deployment to access the application on port 80.

```
kubectl create -f deployments/pacman-deployment-rs.yaml
```

Scale the pacman deployment

```
kubectl scale deploy/pacman --replicas=2
```

Wait until the pacman deployment shows 2 pods available

```
kubectl get deploy pacman -o wide --watch
```

Once the `pacman` service has an IP address for the replica, open up your browser and try to access it via its
DNS e.g. [http://pacman.default.federation.svc.federation.com/](http://pacman.default.federation.svc.federation.com/).
Make sure to replace `federation.com` with your DNS name.

#### Check DNS Updates

You can see all the DNS entries that were created in your [Google DNS Managed Zone](https://console.cloud.google.com/networking/dns/zones).

You can also query them from the command line:

```bash
gcloud dns record-sets list --zone federation --filter='name ~ mongo OR name ~ pacman'
```

Note: You may experience delays in DNS updates and you may need to clear your DNS cache from your client in order to see the updates.

## Play Pac-Man

Go ahead and play a few rounds of Pac-Man and invite your friends and colleagues by giving them your FQDN to your Pac-Man application
e.g. [http://pacman.default.federation.svc.federation.com/](http://pacman.default.federation.svc.federation.com/)
(replace `federation.com` with your DNS name).

The DNS will load balance and resolve to any of the available zones in your federated kubernetes cluster. This is represented by the `Cloud:` and `Zone:`
fields at the top, as well as the `Host:` Pod that it's running on. When you save your score, it will automatically save these fields corresponding
to the instance you were playing on and display it in the High Score list.

See who can get the highest score!

## Migrate Pac-Man to GKE Kubernetes Cluster

Once you've played Pac-Man to verify your application has been properly deployed, we'll migrate the application to the GKE Kubernetes cluster only.

#### Migrate the MongoDB Resources

###### Remove AWS MongoDB Replica from Replica Set

Remove the instance by logging into `PRIMARY` `mongo` CLI:

```bash
kubectl --context=gke_${GCP_PROJECT}_us-west1-b_gce-us-west1 exec -it ${MONGO_POD} -- bash
mongo
```

then executing:

```
rs.remove("mongo.default.federation.svc.us-east-1.federation.com:27017")
```

Check the status until this instance remains the only instance as `PRIMARY`:

```
rs.status()
```

###### Migrate MongoDB Kubernetes Replica Set

Now we will migrate the MongoDB instance away from the east AWS cluster:

```
kubectl annotate deploy/mongo federation.kubernetes.io/deployment-preferences='{"rebalance": true, "clusters": {"gce-us-west1": {"minReplicas": 1, "maxReplicas": 1, "weight": 1},"aws-us-east1": {"minReplicas": 0, "maxReplicas": 0, "weight": 0}}}'
kubectl scale deploy/mongo --replicas=1
```

Wait until the mongo deployment reflects the changes:

```
kubectl get deploy mongo -o wide --watch
```

### Migrate Pac-Man Resources

#### Migrate the Pac-Man Replica Set

We'll need to migrate the Pac-Man game to the us-west cluster.

```
kubectl annotate deploy/pacman federation.kubernetes.io/deployment-preferences='{"rebalance": true, "clusters": {"gce-us-west1": {"minReplicas": 2, "maxReplicas": 2, "weight": 0},"aws-us-east1": {"minReplicas": 0, "maxReplicas": 0, "weight": 0}}}'
```

You can check the `pacman` replica set status but keep in mind we're still keeping 2 replicas:

```
kubectl get deploy pacman -o wide --watch
for c in ${KUBE_FED_CLUSTERS}; do echo; echo ----- ${c} -----; echo; kubectl --context=${c} get pods; echo; done
```

Once the `pacman` replica set reflects the changes, open up your browser and try to access it
using the top-level DNS [http://pacman.default.federation.svc.federation.com/](http://pacman.default.federation.svc.federation.com/).
Make sure to replace `federation.com` with your DNS name. If you try to access the old us-east-1 DNS, it will resolve to the
only available `pacman` DNS, us-west. Note that you may experience a delay in DNS updates and you may need to clear your DNS cache.

#### Check DNS Updates

You can see all the DNS entries that were created in your [Google DNS Managed Zone](https://console.cloud.google.com/networking/dns/zones).

You can also query them from the command line:

```bash
gcloud dns record-sets list --zone federation --filter='name ~ mongo OR name ~ pacman'
```

Note: You may experience delays in DNS updates and you may need to clear your DNS cache from your client in order to see the updates.

#### Play Migrated Pac-Man

Now you should have Pac-Man migrated onto the us-west federated Kubernetes cluster. You can verify any previously persisted data remains available on the
us-west region and continue playing Pac-Man!

## Cleanup

#### Delete Pac-Man Resources

##### Delete Pac-Man Replica Set and Service

Delete Pac-Man deployment and service. Seeing the deployment removed from the federation context may take up to a couple minutes.

```
kubectl delete deploy/pacman svc/pacman
```

#### Delete MongoDB Resources

##### Delete MongoDB Deployment and Service

Delete MongoDB deployment and service. Seeing the deployment removed from the federation context may take up to a couple minutes.

```
kubectl delete deploy/mongo svc/mongo
```

##### Delete MongoDB Persistent Volume Claims

```
for c in ${KUBE_FED_CLUSTERS}; do \
    kubectl --context=${c} delete pvc/mongo-storage; \
done
```

#### Delete DNS entries in Google Cloud DNS

Delete the `mongo` and `pacman` DNS entries that were created in your
[Google DNS Managed Zone](https://console.cloud.google.com/networking/dns/zones).

#### Cleanup rest of federation cluster

Follow these guides to cleanup the clusters:

1. [Steps to clean-up your federation cluster created using kubefed](kubernetes-cluster-federation.md#cleanup).
2. Remove each cluster: [AWS](kubernetes-cluster-aws.md#cleanup) and
   [GKE](kubernetes-cluster-gke-federation.md#delete-kubernetes-clusters)

## Video Demonstration

Here is a video demonstrating the above scenario starting at the point where the Pac-Man application is already deployed on GKE and AWS.

[![Pac-Man Game Video Demonstration](https://img.youtube.com/vi/_-08cBlW8T4/0.jpg)](https://www.youtube.com/watch?v=_-08cBlW8T4)
