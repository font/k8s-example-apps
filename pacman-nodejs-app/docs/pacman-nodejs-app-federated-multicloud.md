# Pac-Man Application On Federated Kubernetes Cluster Across Multiple Public Cloud providers

This guide will walk you through creating multiple Kubernetes clusters spanning multiple public cloud providers
and use a federation control plane to deploy the Pac-Man Node.js application onto each cluster. The Kubernetes clusters
and Pac-Man application will be deployed using the following public cloud providers: Google Cloud Platform, Amazon Web Services, and Azure.

## High-Level Architecture

Below is a diagram demonstrating the architecture of the game across the federated kubernetes cluster after all the steps are completed.

![Pac-Man Game Architecture](images/Kubernetes-Federation-Game-Multi-Cloud.png)

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

#### Create the Federated Kubernetes Clusters

For this part, note that you'll generally want to use a consistent version of Kubernetes when deploying in all of the different
public cloud providers e.g. GCP, AWS, and Azure. Each of the public cloud provider setup guides explain how to do this in more detail.

Follow these steps:

1. [Create 1 GKE Kubernetes clusters in 1 region i.e. us-west](kubernetes-cluster-gke-federation.md#gce-us-west1)
2. [Verify the GKE cluster](kubernetes-cluster-gke-federation.md#verify-the-clusters)
3. [Create Google DNS managed zone for cluster](kubernetes-cluster-gke-federation.md#cluster-dns-managed-zone)
4. [Download and install kubefed and kubectl](kubernetes-cluster-gke-federation.md#download-and-install-kubefed-and-kubectl)
5. [Create and verify 1 AWS Kubernetes cluster in 1 region i.e. us-east](kubernetes-cluster-aws.md)
6. [Create and verify 1 Azure Kubernetes cluster in 1 region i.e. southcentralus](kubernetes-cluster-azure.md)
7. [Using `kubefed` set up a Kubernetes federation containing each of these clusters: GKE, AWS, and Azure.](kubernetes-cluster-federation.md)

#### Export the Cluster Contexts

Using the list of contexts for `kubectl`:

```bash
kubectl config get-contexts --output=name
```

Determine the contexts in your federation and assign them to a variable:

```bash
export CLUSTERS="gce-us-west1 az-us-central1 aws-us-east1"
```

## Create MongoDB Resources

#### Create MongoDB Persistent Volume Claims

Now using the default storage class in each cluster, we'll create the PVC:

```bash
for i in ${CLUSTERS}; do
    kubectl --context=${i} \
        create -f persistentvolumeclaim/mongo-pvc.yaml
done
```

Verify the PVCs are bound in each cluster:

```bash
for i in ${CLUSTERS}; do
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

```bash
kubectl create -f deployments/mongo-deployment-rs.yaml
```

Scale the mongo deployment

```bash
kubectl scale deploy/mongo --replicas=3
```

Wait until the mongo deployment shows 3 pods available

```bash
kubectl get deploy mongo -o wide --watch
```

#### Create the MongoDB Replication Set

We'll have to bootstrap the MongoDB instances to talk to each other in the replication set. For this,
we need to run the following commands on the MongoDB instance you want to designate as the primary (master). For our example,
let's use the GKE us-west1-b instance:

```bash
MONGO_POD=$(kubectl --context=gce-us-west1 get pod \
    --selector="name=mongo" \
    --output=jsonpath='{.items..metadata.name}')
kubectl --context=gce-us-west1 exec -it ${MONGO_POD} -- bash
```

Once inside this pod, make sure all Mongo DNS entries for each region are resolvable. Otherwise the command to
initialize the Mongo replica set below will fail. You can do this by installing DNS utilities such as `dig` and `nslookup` using:

```bash
apt-get update
apt-get -y install dnsutils
```

Then use either `dig` or `nslookup` to perform one of the following lookups for each zone:

```bash
dig mongo.default.federation.svc.us-west1.<DNS_ZONE_NAME> +noall +answer
nslookup mongo.default.federation.svc.us-west1.<DNS_ZONE_NAME>

dig mongo.default.federation.svc.southcentralus.<DNS_ZONE_NAME> +noall +answer
nslookup mongo.default.federation.svc.southcentralus.<DNS_ZONE_NAME>

dig mongo.default.federation.svc.us-east-1.<DNS_ZONE_NAME> +noall +answer
nslookup mongo.default.federation.svc.us-east-1.<DNS_ZONE_NAME>
```

Or check to make sure the load balancer DNS A record contains an IP address for each zone:

```bash
dig mongo.default.federation.svc.<DNS_ZONE_NAME> +noall +answer
nslookup mongo.default.federation.svc.<DNS_ZONE_NAME>
```

Once all regions are resolvable, launch the `mongo` CLI:

```bash
mongo
```

Now we'll create an initial configuration specifying each of the mongos in our replication set. In our example,
we'll use the GKE west, Azure central, and AWS east instances. Make sure to replace `federation.com` with the DNS zone name you created.

```javascript
initcfg = {
        "_id" : "rs0",
        "members" : [
                {
                        "_id" : 0,
                        "host" : "mongo.default.federation.svc.us-west1.federation.com:27017"
                },
                {
                        "_id" : 1,
                        "host" : "mongo.default.federation.svc.southcentralus.federation.com:27017"
                },
                {
                        "_id" : 2,
                        "host" : "mongo.default.federation.svc.us-east-1.federation.com:27017"
                }
        ]
}
```

Initiate the MongoDB replication set:

```javascript
rs.initiate(initcfg)
```

Check the status until this instance shows as `PRIMARY`:

```javascript
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

```bash
kubectl scale deploy/pacman --replicas=3
```

Wait until the pacman deployment shows 3 pods available

```bash
kubectl get deploy pacman -o wide --watch
```

Once the `pacman` service has an IP address for each replica, open up your browser and try to access it via its
DNS e.g. [http://pacman.default.federation.svc.federation.com/](http://pacman.default.federation.svc.federation.com/).
Make sure to replace `federation.com` with your DNS name.

You can also see all the DNS entries that were created in your [Google DNS Managed Zone](https://console.cloud.google.com/networking/dns/zones).

## Play Pac-Man

### Setup Custom CNAME DNS Record

We'll set up an easier DNS record to target our Pac-Man game. Simply create a
CNAME record entry that points to the top level federation DNS record.

First, we export some variables to simplify our future commands.

```bash
ZONE_NAME=federation
DNS_NAME=federation.com.
```

```bash
gcloud dns record-sets transaction start -z=${ZONE_NAME}
gcloud dns record-sets transaction add \
    -z=${ZONE_NAME} \
    --name="pacman.${DNS_NAME}" \
    --type=CNAME \
    --ttl=1 \
    pacman.default.federation.svc.${DNS_NAME}
gcloud dns record-sets transaction execute -z=${ZONE_NAME}
```

Go ahead and play a few rounds of Pac-Man and invite your friends and colleagues by giving them your FQDN to your Pac-Man application
e.g. [http://pacman.federation.com/](http://pacman.federation.com/)
(replace `federation.com` with your DNS name).

The DNS will load balance and resolve to any one of the zones in your federated kubernetes cluster. This is represented by the `Cloud:` and `Zone:`
fields at the top, as well as the `Host:` Pod that it's running on. When you save your score, it will automatically save these fields corresponding
to the instance you were playing on and display it in the High Score list.

See who can get the highest score!

## Cleanup

#### Delete Pac-Man Resources

##### Delete Pac-Man Deployment and Service

Delete Pac-Man deployment and service. Seeing the deployment removed from the federation context may take up to a couple minutes.

```bash
kubectl delete deploy/pacman svc/pacman
```

#### Delete MongoDB Resources

##### Delete MongoDB Deployment and Service

Delete MongoDB deployment and service. Seeing the deployment removed from the federation context may take up to a couple minutes.

```bash
kubectl delete deploy/mongo svc/mongo
```

##### Delete MongoDB Persistent Volume Claims

```bash
for i in ${CLUSTERS}; do \
    kubectl --context=${i} delete pvc/mongo-storage; \
done
```

#### Delete DNS entries in Google Cloud DNS

Delete the `mongo` and `pacman` DNS entries that were created in your
[Google DNS Managed Zone](https://console.cloud.google.com/networking/dns/zones).

#### Cleanup rest of federation cluster

Follow these guides to cleanup the clusters:

1. [Steps to clean-up your federation cluster created using kubefed](kubernetes-cluster-federation.md#cleanup).
2. Remove each cluster: [Azure](kubernetes-cluster-azure.md#cleanup),
   [AWS](kubernetes-cluster-aws.md#cleanup), and [GKE](kubernetes-cluster-gke-federation.md#delete-kubernetes-clusters)

#### Remove kubectl config contexts

Remove kubectl contexts:

```bash
for i in ${CLUSTERS}; do \
    kubectl config delete-context ${i}
done
```
