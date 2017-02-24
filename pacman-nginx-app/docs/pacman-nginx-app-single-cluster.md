# Pac-Man NGINX App On Single Kubernetes Cluster

This guide will walk you through creating a single Kubernetes cluster and deploy the Pac-Man NGINX application onto it.

## Create the Kubernetes cluster

Using the command below we'll create a cluster:

- Use the project ID you previously created
- Cluster named **kube-ref-app**
- Zone will be **us-central1-f** or use a zone closest to you
- Machine type will be **n1-standard-2**
- Size of 3 nodes

```
gcloud container --project "<YOUR_PROJECT_ID>" \
clusters create "kube-ref-app" --zone "us-central1-f" \
--machine-type "n1-standard-2" --num-nodes "3" --network "default"
```

Once the cluster has been created, you'll want to log into the cluster:

```
gcloud container clusters get-credentials kube-ref-app
```

## Creating the MongoDB Service

### Create a persistent disk to store the data

This allows us to not lose our data as pods come and go. To create the disk, run:

```
gcloud compute disks create \
  --project "<YOUR_PROJECT_ID>" \
  --zone "us-central1-f" \
  --size 200GB \
  mongo-disk
```

Be sure to use your project's ID and the zone that you selected for your cluster.

### Create MongoDB replication controller

Now create the  MongoDB replication controller that will use the `gcePersistentDisk` volume plugin to mount
the `mongo-disk` we just created:

```
kubectl create -f controllers/mongo-controller.yaml
```

### Create the MongoDB service

This component creates a mongo DNS entry, so this is why we use `mongo` as the host we connect to in our application instead of `localhost`.

```
kubectl create -f services/mongo-service.yaml
```

Verify the container has been created and is in the running state:

```
kubectl get pods -o wide --watch
```

## Creating the Web Application Server

We'll need to create the web server replication controller, this time with 2 replicas, and the service to access the application on port 80.

```
kubectl create -f controllers/web-controller.yaml
kubectl create -f services/web-service.yaml
```

Wait until their status is running:

```
kubectl get pods -o wide --watch
```

Also verify the service has an external IP:

```
kubectl get svc -o wide
```

Once the `web` service has an IP address, open up your browser and try to access it via `http://<EXTERNAL_IP>/`.
