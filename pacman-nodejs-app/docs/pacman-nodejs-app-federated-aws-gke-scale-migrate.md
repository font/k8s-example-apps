# Pac-Man Application On Federated Kubernetes Cluster With Public Cloud Provider Migration

This guide will walk you through creating multiple Kubernetes clusters spanning multiple public cloud providers
and use a federation control plane to deploy the Pac-Man Node.js application onto one cluster (AWS), then migrate it to another cluster
running on a different public cloud provider (GCP).

## High-Level Architecture

Below is a diagram demonstrating the architecture of the game across the federated kubernetes cluster after all the steps are completed.

![Pac-Man Game Architecture](images/Kubernetes-Federation-Game-AWS-GKE-Migration.png)

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
export KUBE_FED_CLUSTERS="us-east-1.subdomain.example.com"
```

## Create MongoDB Resources

#### Create MongoDB Persistent Volume Claims

Create the PVC:

```bash
kubectl --context=us-east-1.subdomain.example.com \
    create -f persistentvolumeclaim/mongo-pvc.yaml
```

Verify the PVCs are bound in each cluster:

```bash
kubectl --context=us-east-1.subdomain.example.com \
        get pvc mongo-storage
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

Annotate the mongo deployment

```
kubectl annotate deploy/mongo federation.kubernetes.io/deployment-preferences='{"rebalance": true, "clusters": {"gce-us-west1": {"minReplicas": 0, "maxReplicas": 0, "weight": 0},"aws-us-east1": {"minReplicas": 1, "maxReplicas": 1, "weight": 1}}}'
```

Scale the mongo deployment

```
kubectl scale deploy/mongo --replicas=1
```

Wait until the mongo deployment shows 1 pod available

```
kubectl get deploy mongo -o wide --watch
```

#### Create the MongoDB Replication Set

We'll have to bootstrap the MongoDB instances to create the replication set. For this,
we need to run the following commands on the MongoDB instance you want to designate as the primary (master). For our example,
let's use the GKE us-west1-b instance:

```bash
MONGO_POD=$(kubectl --context=us-east-1.subdomain.example.com get pod \
    --selector="name=mongo" \
    --output=jsonpath='{.items..metadata.name}')
kubectl --context=us-east-1.subdomain.example.com exec -it ${MONGO_POD} -- bash
```

Once inside this pod, make sure all Mongo DNS entries are resolvable. Otherwise the command to
initialize the Mongo replica set below will fail. You can do this by installing DNS utilities such as `dig` and `nslookup` using:

```bash
apt-get update
apt-get -y install dnsutils
```

Then use either `dig` or `nslookup` to perform the following lookup:

```bash
dig mongo.default.federation.svc.us-east-1.<DNS_ZONE_NAME> +noall +answer
nslookup mongo.default.federation.svc.us-east-1.<DNS_ZONE_NAME>
```

Or check to make sure the load balancer DNS A record contains an IP address:

```bash
dig mongo.default.federation.svc.<DNS_ZONE_NAME> +noall +answer
nslookup mongo.default.federation.svc.<DNS_ZONE_NAME>
```

Once the DNS entries are resolvable, launch the `mongo` CLI:

```bash
mongo
```

Now we'll create an initial configuration specifying the one mongo in our replication set. In our example,
we'll use the AWS east instance. Make sure to replace `example.com` with the DNS zone name you created.

```
initcfg = {
        "_id" : "rs0",
        "members" : [
                {
                        "_id" : 0,
                        "host" : "mongo.default.federation.svc.us-east-1.example.com:27017"
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

Once you have the instance showing up as `PRIMARY`, you have a working MongoDB replica set
that will replicate data across any of the replica set members in the federated cluster.

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

Annotate the mongo deployment

```
kubectl annotate deploy/pacman federation.kubernetes.io/deployment-preferences='{"rebalance": true, "clusters": {"gce-us-west1": {"minReplicas": 0, "maxReplicas": 0, "weight": 0},"aws-us-east1": {"minReplicas": 1, "maxReplicas": 1, "weight": 1}}}'
```


Scale the pacman deployment

```
kubectl scale deploy/pacman --replicas=3
```

Wait until the pacman deployment shows 3 pods available

```
kubectl get deploy pacman -o wide --watch
```

Once the `pacman` service has an IP address for the replica, open up your browser and try to access it via its
DNS e.g. [http://pacman.default.federation.svc.example.com/](http://pacman.default.federation.svc.example.com/).
Make sure to replace `example.com` with your DNS name.

You can also see all the DNS entries that were created in your [Google DNS Managed Zone](https://console.cloud.google.com/networking/dns/zones).

## Play Pac-Man

Go ahead and play a few rounds of Pac-Man and invite your friends and colleagues by giving them your FQDN to your Pac-Man application
e.g. [http://pacman.default.federation.svc.example.com/](http://pacman.default.federation.svc.example.com/)
(replace `example.com` with your DNS name).

The DNS will load balance and resolve to any of the available zones in your federated kubernetes cluster. This is represented by the `Cloud:` and `Zone:`
fields at the top, as well as the `Host:` Pod that it's running on. When you save your score, it will automatically save these fields corresponding
to the instance you were playing on and display it in the High Score list.

See who can get the highest score!

## Scale Pac-Man to GKE Kubernetes Cluster

Once you've played Pac-Man to verify your application has been properly deployed, we'll scale the application to the GKE Kubernetes cluster.

#### Export the Cluster Contexts

Using the list of contexts for `kubectl`:

```bash
kubectl config get-contexts --output=name
```

Add the GKE federation context to your variable:

```bash
export KUBE_FED_CLUSTERS="gke_${GCP_PROJECT}_us-west1-b_gce-us-west1 us-east-1.subdomain.example.com"
```

#### Scale the MongoDB Resources

###### Create MongoDB Persistent Volume Claims

Now that we have the storage class created in the cluster we'll create the PVC:

```bash
for i in ${KUBE_FED_CLUSTERS}; do
    kubectl --context=${i} \
        create -f persistentvolumeclaim/mongo-pvc.yaml
done
```

Verify the PVC is bound in the cluster:

```bash
for i in ${KUBE_FED_CLUSTERS}; do
    kubectl --context=${i} \
        get pvc mongo-storage
done
```

###### Scale MongoDB Kubernetes Replica Set

Now scale the MongoDB Replica Set that will use the `mongo-storage` persistent volume claim to mount the
directory that is to contain the MongoDB database files. In addition, we will add the new MongoDB replica to the existing replica set
in order to replicate the MongoDB data set across to the GKE cluster.

```
kubectl annotate deploy/mongo federation.kubernetes.io/deployment-preferences='{"rebalance": true, "clusters": {"gce-us-west1": {"minReplicas": 1, "maxReplicas": 1, "weight": 1},"aws-us-east1": {"minReplicas": 1, "maxReplicas": 1, "weight": 1}}}'
kubectl scale deploy/mongo --replicas=2
```

Wait until the mongo deployment reflects the changes:

```
kubectl get deploy mongo -o wide --watch
```

###### Scale the MongoDB Deployment

We'll have to add the MongoDB instance to the existing MongoDB replica set. For this, we need to run the following command on the MongoDB
instance you designated as the primary (master). For our example, we used the us-east-1a instance so let's re-use it:

```
kubectl --context=us-east-1.subdomain.example.com exec -it ${MONGO_POD} -- bash
```

Once inside this pod, feel free to make sure the new Mongo DNS entry for the us-west1 region is resolvable. Otherwise the command to
add to the Mongo replica set below will fail. You can try to add to the Mongo replica set first and come back here if you have problems.
You can verify the Mongo DNS entries by installing DNS utilities such as `dig` and `nslookup` using:

```
apt-get update
apt-get -y install dnsutils
```

Then use either `dig` or `nslookup` to perform the following lookup for the us-east zone:

```
dig mongo.default.federation.svc.us-west1.<DNS_ZONE_NAME> +noall +answer
nslookup mongo.default.federation.svc.us-west1.<DNS_ZONE_NAME>
```

Also check to make sure the load balancer DNS A record contains an IP address for each zone:

```
dig mongo.default.federation.svc.<DNS_ZONE_NAME> +noall +answer
nslookup mongo.default.federation.svc.<DNS_ZONE_NAME>
```

Once all regions are resolvable, launch the `mongo` CLI:

```
mongo
```

Now we'll add the new mongo to our replication set. In our example,
we'll be adding the us-west instance. Make sure to replace `example.com` with the DNS zone name you created.

Add to the MongoDB replication set:

```
rs.add('mongo.default.federation.svc.us-west1.example.com:27017')
```

Check the status until the new instance shows as `SECONDARY`:

```
rs.status()
```

Once you have the instance showing up as `SECONDARY`, you have added a MongoDB instance to the replica set that will replicate data across to the new cluster.

Go ahead and exit out of the Mongo CLI and out of the Pod.

### Scale Pac-Man Resources

#### Scale the Pac-Man Deployment

We'll need to scale the Pac-Man game to the new cluster.

```
kubectl annotate deploy/pacman federation.kubernetes.io/deployment-preferences='{"rebalance": true, "clusters": {"gce-us-west1": {"minReplicas": 1, "maxReplicas": 1, "weight": 1},"aws-us-east1": {"minReplicas": 1, "maxReplicas": 1, "weight": 1}}}'
kubectl scale deploy/mongo --replicas=2

```

Wait until the deployment reflects the changes:

```
kubectl get deploy pacman -o wide --watch
```

Once the new `pacman` replica set is ready, open up your browser and try to access it via its specific
DNS e.g. [http://pacman.default.federation.svc.us-west1.example.com/](http://pacman.default.federation.svc.us-west1.example.com/) or
using the top-level DNS [http://pacman.default.federation.svc.example.com/](http://pacman.default.federation.svc.example.com/).
Make sure to replace `example.com` with your DNS name.

You can also see all the DNS entries that were updated in your [Google DNS Managed Zone](https://console.cloud.google.com/networking/dns/zones).

#### Play Scale out Pac-Man

Now you should have Pac-Man scaled onto a new federated Kubernetes cluster. You can verify any previously persisted data has been replicated to the
new us-west region and continue playing Pac-Man!

## Migrate Pac-Man to GKE Kubernetes Cluster

Once you've played Pac-Man to verify your application has been properly scaled, we'll migrate the application to the GKE Kubernetes cluster only.

#### Migrate the MongoDB Resources

###### Migrate the MongoDB Replication Set

To force a MongoDB member to be primary using database commands without going through a failure scenario to elect a new primary,
we'll need to log into the MongoDB primary instance and force it to step down. For this, we need to run the following command on the MongoDB
instance you designated as the primary (master). For our example, we used the us-east-1a instance so let's re-use it:

```
kubectl --context=us-east-1.subdomain.example.com exec -it ${MONGO_POD} -- bash
```

Launch the `mongo` CLI:

```
mongo
```

Now we'll force this primary (master) instance to step down so that the us-west instance becomes the new primary (master) instance.

Step down the MongoDB replication set primary instance for 120 seconds:

```
rs.stepDown(120)
```

*mongo.default.federation.svc.us-west1.example.com becomes primary*

Check the status until the us-west instance shows as `PRIMARY`:

```
rs.status()
```

Once you've made the MongoDB instances reverse roles, go ahead and exit out of the Mongo CLI and out of the Pod.

###### Migrate MongoDB Kubernetes Replica Set

Now that we have the GKE us-west MongoDB instance as the new primary, we will migrate the MongoDB instance away from the
east AWS cluster:

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
kubectl annotate deploy/pacman federation.kubernetes.io/deployment-preferences='{"rebalance": true, "clusters": {"gce-us-west1": {"minReplicas": 1, "maxReplicas": 1, "weight": 1},"aws-us-east1": {"minReplicas": 0, "maxReplicas": 0, "weight": 0}}}'
kubectl scale deploy/pacman --replicas=1
```

Wait until the deployment reflects the changes:

```
kubectl get deploy pacman -o wide --watch
```

Once the new `pacman` replica set is ready, open up your browser and try to access it
using the top-level DNS [http://pacman.default.federation.svc.example.com/](http://pacman.default.federation.svc.example.com/).
Make sure to replace `example.com` with your DNS name. If you try to access the old us-east-1 DNS, it will resolve to the
only available DNS.

You can also see all the DNS entries that were updated in your [Google DNS Managed Zone](https://console.cloud.google.com/networking/dns/zones).

#### Play Migrated Pac-Man

Now you should have Pac-Man migrated onto the us-west federated Kubernetes cluster. You can verify any previously persisted data remains available on the
us-west region and continue playing Pac-Man!

## Cleanup

#### Delete Pac-Man Resources

##### Delete Pac-Man Deployment and Service

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

```bash
for i in ${KUBE_FED_CLUSTERS}; do
    kubectl --context=${i} \
    delete -f persistentvolumeclaim/mongo-pvc.yaml
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
