# Kubernetes Migration Tool

This tool is a proof-of-concept to help demonstrate an application migration use-case. The application of choice is Pac-Man. It will be migrated from
cluster A to cluster B.

## Setup Pac-Man Application On Cluster A

### Create Kubernetes Clusters

#### US West

```bash
gcloud container clusters create gce-us-west1 \
    --zone=us-west1-b \
    --scopes "cloud-platform,storage-ro,logging-write,monitoring-write,service-control,service-management,https://www.googleapis.com/auth/ndev.clouddns.readwrite"
```

#### US Central

```bash
gcloud container clusters create gce-us-central1 \
    --zone=us-central1-b \
    --scopes "cloud-platform,storage-ro,logging-write,monitoring-write,service-control,service-management,https://www.googleapis.com/auth/ndev.clouddns.readwrite"
```

### Use US West cluster context

```bash
export GCP_PROJECT=$(gcloud config list --format='value(core.project)')
```

```bash
kubectl config use-context gke_${GCP_PROJECT}_us-west1-b_gce-us-west1
```

### Create and Use pacman Namespace

```bash
kubectl create namespace pacman
```

```bash
kubectl config set-context gke_${GCP_PROJECT}_us-west1-b_gce-us-west1 --namespace pacman
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

Wait until the mongo service has the external IP address listed:

```bash
kubectl get svc mongo -o wide --watch
```

#### Create MongoDB Deployment

Now create the MongoDB Deployment that will use the `mongo-storage` persistent volume claim to mount the
directory that is to contain the MongoDB database files. In addition, we will pass the `--replSet rs0` parameter
to `mongod` in order to create a MongoDB replica set.

```
kubectl create -f deployments/mongo-deployment-rs.yaml
```

Scale the deployment, since the deployment definition has replicas set to 0:

```
kubectl scale deploy/mongo --replicas=1
```

Verify the container has been created and is in the running state:

```
kubectl get pods -o wide --watch
```

#### Create the MongoDB Replication Set

We'll have to bootstrap the MongoDB instance since we're using a replication set. For this,
we need to run the following commands on the MongoDB instance you want to designate as the primary (master). For our example,
we're using the us-west1-b instance:

```
MONGO_POD=$(kubectl --context=gke_${GCP_PROJECT}_us-west1-b_gce-us-west1 get pod \
    --selector="name=mongo" \
    --output=jsonpath='{.items..metadata.name}')
kubectl --context=gke_${GCP_PROJECT}_us-west1-b_gce-us-west1 exec -it ${MONGO_POD} -- bash
```

Once inside this pod, make sure the Mongo DNS entry you plan to use is resolvable. Otherwise the command to initialize the Mongo
replica set below will fail. You can do this by installing DNS utilities such as `dig` and `nslookup` using:

**NOTE: If you're using the load balancer IP address, you can skip this step.**

```
apt-get update
apt-get -y install dnsutils
```

Then use either `dig` or `nslookup` to perform one of the following lookups:

```
dig mongo.us-west1.<DNS_ZONE_NAME> +noall +answer
nslookup mongo.us-west1.<DNS_ZONE_NAME>
```

Once they are resolvable, launch the `mongo` CLI:

```
mongo
```

Now we'll create an initial configuration specifying just this mongo in our replication set. In our example,
we'll use the west instance. Make sure to replace `<DNS_ZONE_NAME>.com` with the DNS zone name you created.

```
initcfg = {
        "_id" : "rs0",
        "members" : [
                {
                        "_id" : 0,
                        "host" : "mongo.us-west1.<DNS_ZONE_NAME>.com:27017"
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

Once you have this instance showing up as `PRIMARY`, you have a working MongoDB replica set that will replicate data.

Go ahead and exit out of the Mongo CLI and out of the Pod.

## Creating the Pac-Man Resources

#### Create Pac-Man Service

This component creates the service to access the application.

```
kubectl create -f services/pacman-service.yaml
```

Wait until the pacman service has the external IP address listed:

```
kubectl get svc pacman -o wide --watch
```

#### Create Pac-Man Deployment

Now create the Pac-Man deployment.

```
kubectl create -f deployments/pacman-deployment-rs.yaml
```

Scale the deployment, since the deployment definition has replicas set to 0.

```
kubectl scale deploy/pacman --replicas=2
```

Verify the containers have been created and are in the running state:

```
kubectl get pods -o wide --watch
```

Once the pacman pods are running and the `pacman` service has an IP address, open up your browser and try to access it via `http://<EXTERNAL_IP>/`.

#### Save Pac-Man Load Balancer IP

```
PACMAN_PUBLIC_IP=$(kubectl get svc pacman  --output jsonpath="{.status.loadBalancer.ingress[0].ip}")
```

#### Add DNS A record

```bash
gcloud dns record-sets transaction start -z=zonename
gcloud dns record-sets transaction add -z=zonename --name="pacman.example.com" --type=A --ttl=1 "${PACMAN_PUBLIC_IP}"
gcloud dns record-sets transaction execute -z=zonename
```

## Migrate Pac-Man Application Onto Cluster B

In addition to the above setup, in order to perform this migration, the tool makes the following assumptions:

1. GKE is used for both cluster A and cluster B
2. Cluster A is in the us-west-1b region
3. Cluster B is in the us-central-1b region
4. Both clusters are making use of Google Cloud DNS
5. Both clusters are using the same Google Cloud Platform project ID
6. gcloud command is installed and working on client to access both clusters
7. kubectl is installed and configured to access both clusters using the provided contexts

