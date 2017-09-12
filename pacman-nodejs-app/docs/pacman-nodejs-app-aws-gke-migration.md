# Pac-Man AWS GKE Migration

This tutorial walks you through the steps to perform a Pac-Man migration from an AWS cluster A to a GKE cluster B using GKE to manage DNS. The tutorial documents the steps
required to set up cluster A, and documents how to migrate it to cluster B manually or using the automated `kmt` proof-of-concept tool.

## Prerequisites
If you have not already done so, follow [these steps](../README.md#prerequisites) to Clone the required repository, create the Pac-Man container image, set up Google Cloud SDK and push the container image.

## Setup Your AWS cluster (Cluster A)
1. Follow [these steps](https://github.com/kubernetes/kops#installing) to install kops

2. And [these steps](kubernetes-cluster-aws.md#setup-your-aws-environment) to setup your AWS environment.(Stop at the Configure DNS section).

3. Store your desired subdomain for the aws cluster:

* Since we will be using this subdomain extensively in this tutorial, we will store it in an environment variable for ease

```bash
export SUBDOMAIN=subdomain.example.com
```
4. Follow [these steps](https://github.com/kubernetes/kops/blob/master/docs/aws.md#scenario-3-subdomain-for-clusters-in-route53-leaving-the-domain-at-another-registrar) to configure DNS.
* **Make sure to [test your DNS setup](https://github.com/kubernetes/kops/blob/master/docs/aws.md#testing-your-dns-setup) before moving on.**

5. Follow [these steps](https://github.com/kubernetes/kops/blob/master/docs/aws.md#cluster-state-storage) to create a dedicated S3 bucket.

6. Create and verify the AWS Kubernetes cluster following [these steps and using the subdomain configured above](kubernetes-cluster-aws.md#create-the-kubernetes-cluster).

## Setup Your GKE cluster (Cluster B)

Follow [these instructions](kubernetes-cluster-gke-federation.md#create-the-kubernetes-clusters)
to create 1 GKE Kubernetes cluster in 1 region. This tutorial will use us-west so if you use a different region
then modify the commands appropriately.

### Store the GCP Project Name

```bash
export GCP_PROJECT=$(gcloud config list --format='value(core.project)')
```

## Setup Pac-Man Application On AWS Cluster


```bash
kubectl config use-context ${SUBDOMAIN}
```

### Create and Use pacman Namespace

```bash
kubectl create namespace pacman
```

```bash
kubectl config set-context ${SUBDOMAIN} --namespace pacman
```

### Create MongoDB Resources

#### Create MongoDB Persistent Volume Claim

We need to create persistent volume claim for our MongoDB to persist the database.

```bash
kubectl create -f persistentvolumeclaim/mongo-pvc.yaml
```

Wait until the pvc is bound:

```bash
kubectl get pvc mongo-storage -o wide --watch
```

#### Create MongoDB Service

This component creates a mongo DNS entry, so this is why we use `mongo` as the host we connect to in our application instead of `localhost`.

```bash
kubectl create -f services/mongo-service.yaml
```

Wait until the mongo service has the dynamic DNS address listed:

```bash
kubectl get svc mongo -o wide --watch
```

#### Create MongoDB Deployment

Now create the MongoDB Deployment that will use the `mongo-storage` persistent volume claim to mount the
directory that is to contain the MongoDB database files. In addition, we will pass the `--replSet rs0` parameter
to `mongod` in order to create a MongoDB replica set.

```bash
kubectl create -f deployments/mongo-deployment-rs.yaml
```

Scale the deployment, since the deployment definition has replicas set to 0:

```bash
kubectl scale deploy/mongo --replicas=1
```

Verify the container has been created and is in the running state:

```bash
kubectl get pods -o wide --watch
```

#### Save MongoDB Load Balancer Hostname

```bash
MONGO_SRC_PUBLIC_HOSTNAME=$(kubectl get svc mongo --output jsonpath="{.status.loadBalancer.ingress[0].hostname}")
```

#### Create the MongoDB Replication Set

We'll have to bootstrap the MongoDB instance since we're using a replication set. For this,
we need to run the following command on the MongoDB instance you want to designate as the primary (master):

```bash
MONGO_SRC_POD=$(kubectl --context=${SUBDOMAIN} get pod \
    --selector="name=mongo" \
    --output=jsonpath='{.items..metadata.name}')
kubectl --context=${SUBDOMAIN} \
    exec -it ${MONGO_SRC_POD} -- \
    mongo --eval "rs.initiate({
                    '_id' : 'rs0',
                    'members' : [
                        {
                            '_id' : 0,
                            'host' : \"${MONGO_SRC_PUBLIC_HOSTNAME}:27017\"
                        }
                    ]
                })"
```

Check the status until this instance shows as `PRIMARY`:

```
kubectl --context=${SUBDOMAIN} \
    exec -it ${MONGO_SRC_POD} -- \
    mongo --eval "rs.status()"
```

Once you have this instance showing up as `PRIMARY`, you have a working MongoDB replica set that will replicate data.

Go ahead and exit out of the Mongo CLI and out of the Pod.

### Creating the Pac-Man Resources

#### Create Pac-Man Service

This component creates the service to access the application.

```bash
kubectl create -f services/pacman-service.yaml
```

Wait until the pacman service has the dynamic DNS address listed:

```bash
kubectl get svc pacman -o wide --watch
```

#### Create Pac-Man Deployment

Now create the Pac-Man deployment.

```bash
kubectl create -f deployments/pacman-deployment-rs.yaml
```

Scale the deployment, since the deployment definition has replicas set to 0.

```bash
kubectl scale deploy/pacman --replicas=2
```

Verify the containers have been created and are in the running state:

```bash
kubectl get pods -o wide --watch
```

#### Save Pac-Man Load Balancer Hostname

```bash
PACMAN_SRC_PUBLIC_HOSTNAME=$(kubectl get svc pacman --output jsonpath="{.status.loadBalancer.ingress[0].hostname}".)

```

#### Add DNS CNAME record

Set the value of your `ZONE_NAME` and `DNS_NAME` name used for your Google Cloud DNS configuration.

```bash
ZONE_NAME=zonename
DNS_NAME=example.com.
```

Then execute the below commands:

```bash
gcloud dns record-sets transaction start -z=${ZONE_NAME}
gcloud dns record-sets transaction add -z=${ZONE_NAME} --name="pacman.${DNS_NAME}" --type=CNAME --ttl=1 "${PACMAN_SRC_PUBLIC_HOSTNAME}"
gcloud dns record-sets transaction execute -z=${ZONE_NAME}
```

## Play Pac-Man

Go ahead and play a few rounds of Pac-Man and invite your friends and colleagues by giving them your FQDN to your Pac-Man application
e.g. [http://pacman.example.com/](http://pacman.example.com/) (replace `example.com` with your DNS name).

The `Zone:` field at the top represents the zone you're game is running in. When you save your score, it will automatically save the
zone you were playing in and display it in the High Score list.

See who can get the highest score!

## Migrate Pac-Man Application to Cluster B (Manually)

### Save cluster resources in pacman namespace

Create dump directory:

```bash
mkdir ./pacman-ns-dump
```

Export desired namespace:

```bash
kubectl get --export -o=json ns | jq '.items[] |
select(.metadata.name=="pacman") |
del(.status,
        .metadata.uid,
        .metadata.selfLink,
        .metadata.resourceVersion,
        .metadata.creationTimestamp,
        .metadata.generation
    )' > ./pacman-ns-dump/ns.json

```

Export desired resources from namespace:

```bash
for ns in $(jq -r '.metadata.name' < ./pacman-ns-dump/ns.json);do
    echo "Namespace: $ns"
    kubectl --namespace="${ns}" get --export -o=json pvc,secrets,svc,deploy,rc,ds | \
    jq '.items[] |
        select(.type!="kubernetes.io/service-account-token") |
        del(
            .spec.clusterIP,
            .metadata.uid,
            .metadata.selfLink,
            .metadata.resourceVersion,
            .metadata.creationTimestamp,
            .metadata.generation,
            .metadata.annotations,
            .status,
            .spec.template.spec.securityContext,
            .spec.template.spec.dnsPolicy,
            .spec.template.spec.terminationGracePeriodSeconds,
            .spec.template.spec.restartPolicy,
            .spec.storageClassName,
            .spec.volumeName
        )' > "./pacman-ns-dump/pacman-ns-dump.json"
done
```

### Switch Contexts to Cluster B (Destination)

We will be migrating to our US West region:

```bash
kubectl config use-context gke_${GCP_PROJECT}_us-west1-b_gce-us-west1
```

### Create and Use the pacman Namespace

Create the namespace needed for the migration:

```bash
kubectl create -f pacman-ns-dump/ns.json
```

Set the namespace of the context:

```bash
kubectl config set-context gke_${GCP_PROJECT}_us-west1-b_gce-us-west1 --namespace pacman
```

### Create Pac-Man Kubernetes Resources

Add the exported resources into the namespace:

```bash
kubectl create -f pacman-ns-dump/pacman-ns-dump.json
```

### Verify All Resources

All resources are ready and available after all pods are in the `RUNNING` state or their corresponding deployments show the correct number of pods `AVAILABLE`.
Also when all services show an `EXTERNAL-IP`.

```bash
kubectl get all -o wide
```

### Save Pac-Man and MongoDB Load Balancer IP

```bash
PACMAN_DST_PUBLIC_IP=$(kubectl get svc pacman --output jsonpath="{.status.loadBalancer.ingress[0].ip}")
MONGO_DST_PUBLIC_IP=$(kubectl get svc mongo --output jsonpath="{.status.loadBalancer.ingress[0].ip}")
```

### Add New Mongo Instance to Replica Set

Connect to the mongo pod in cluster A and invoke the mongo client to connect to the mongodb PRIMARY in order to add the new mongo instance as a replica set SECONDARY.

```bash
kubectl --context=${SUBDOMAIN} \
    exec -it ${MONGO_SRC_POD} -- \
    mongo --eval "rs.add(\"${MONGO_DST_PUBLIC_IP}:27017\")"
```

### Check Status of New Mongo Instance In Replica Set

```bash
kubectl --context=${SUBDOMAIN} \
    exec -it ${MONGO_SRC_POD} -- \
    mongo --eval "rs.status()"
```

### Make New Mongo Instance Primary

```bash
kubectl --context=${SUBDOMAIN} \
    exec -it ${MONGO_SRC_POD} -- \
    mongo --eval "rs.stepDown(120)"
```

### Update DNS

Update DNS to point to new cluster:

```bash
gcloud dns record-sets transaction start -z=${ZONE_NAME}
gcloud dns record-sets transaction remove -z=${ZONE_NAME} --name="pacman.${DNS_NAME}" --type=CNAME --ttl=1 "${PACMAN_SRC_PUBLIC_HOSTNAME}"
gcloud dns record-sets transaction add -z=${ZONE_NAME} --name="pacman.${DNS_NAME}" --type=A --ttl=1 "${PACMAN_DST_PUBLIC_IP}"
gcloud dns record-sets transaction execute -z=${ZONE_NAME}
```

### Remove Old Mongo Instance From Replica Set

```bash
MONGO_DST_POD=$(kubectl --context=gke_${GCP_PROJECT}_us-west1-b_gce-us-west1 get pod \
    --selector="name=mongo" \
    --output=jsonpath='{.items..metadata.name}')
kubectl --context=gke_${GCP_PROJECT}_us-west1-b_gce-us-west1 \
    exec -it ${MONGO_DST_POD} -- \
    mongo --eval "rs.remove(\"${MONGO_SRC_PUBLIC_HOSTNAME}:27017\")"
```

### Check Status to Verify Removal

```bash
kubectl --context=gke_${GCP_PROJECT}_us-west1-b_gce-us-west1 \
    exec -it ${MONGO_DST_POD} -- \
    mongo --eval "rs.status()"
```

### Remove Old Pac-man Cluster Resources

```bash
kubectl --context ${SUBDOMAIN} \
    delete ns pacman
```

## Migrate Pac-Man Application to Cluster B (Automated)

### Prerequisites

To perform this migration, the tool makes the following assumptions:

1. AWS is used for cluster A and GKE is used for cluster B.
2. Pac-Man is already deployed and working in cluster A. See above for steps.
3. Both clusters are making use of Google Cloud DNS to manage DNS entries. [See here for more details](https://cloud.google.com/dns/migrating).
4. Google Cloud DNS managed zone is already created in your Google Cloud Platform project.
   [See here for instructions](kubernetes-cluster-gke-federation.md#cluster-dns-managed-zone).
5. `gcloud` cloud SDK is installed and working on client to manage Google Cloud DNS. [See here for instructions](https://cloud.google.com/sdk/).
6. `kubectl` is installed and configured to access both clusters using the provided contexts.
7. `jq` is installed on the host machine that will be executing `kmt`. [See here for installation instructions](https://github.com/stedolan/jq/wiki/Installation).

Execute the following command to migrate Pac-Man from the AWS cluster to the GKE cluster in the us-west1-b region.

```bash
cd tools/migrate
./kmt.sh -f ${SUBDOMAIN} \
    -t gke_${GCP_PROJECT}_us-west1-b_gce-us-west1 \
    -n pacman \
    -z ${ZONE_NAME} \
    -d ${DNS_NAME} &> kmt.log
```

Then from another window you can tail the log:

```bash
tail -f kmt.log
```

See [here for more details](../tools/migrate) about using the `kmt` tool.

## Cleanup

### Cleanup AWS Cluster

Follow [these steps](kubernetes-cluster-aws.md#cleanup) to clean up your aws cluster.

### Cleanup Pac-Man Namespace

```bash
gcloud dns record-sets transaction start -z=${ZONE_NAME}
gcloud dns record-sets transaction remove -z=${ZONE_NAME} \
    --name="pacman.${DNS_NAME}" --type=A --ttl=1 "${PACMAN_DST_PUBLIC_IP}"
gcloud dns record-sets transaction execute -z=${ZONE_NAME}
```

```bash
kubectl --context=gke_${GCP_PROJECT}_us-west1-b_gce-us-west1 \
    delete ns pacman
```

### Remove Kubernetes Clusters

Follow [these instructions](kubernetes-cluster-gke-federation.md#delete-kubernetes-clusters)
to delete the GKE cluster in us-west.

## Video Demonstration

Here is a playlist with 3 videos demonstrating the AWS <-> GKE migration using the `kmt` tool:

1. Intro to Pac-Man and showing current state (AWS)
2. Migration from AWS to GKE
3. Migration from GKE to AWS

[![Pac-Man Game AWS GKE Migration Video Demonstration using KMT](https://img.youtube.com/vi/HHva5npIjmU/0.jpg)](https://www.youtube.com/playlist?list=PLDywARKHDjG8KhUA-hmdQQQunUodGfN3G)
