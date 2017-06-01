# Pac-Man Node.js App On Single Kubernetes Cluster

This guide will walk you through creating a single Kubernetes cluster and deploy the Pac-Man Node.js application onto it.

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
gcloud container clusters \
  --project "<YOUR_PROJECT_ID>" \
  --zone "us-central1-f" \
  get-credentials kube-ref-app
```

## Create MongoDB Resources

#### Create MongoDB Persistent Volume Claim

We need to create persistent volume claim for our MongoDB to persist the database.

```
kubectl create -f persistentvolumeclaim/mongo-pvc.yaml
```

Wait until the pvc is bound:

```
kubectl get pvc mongo-storage -o wide --watch
```

#### Create MongoDB Service

This component creates a mongo DNS entry, so this is why we use `mongo` as the host we connect to in our application instead of `localhost`.

```
kubectl create -f services/mongo-service.yaml
```

Wait until the mongo service has the external IP address listed:

```
kubectl get svc mongo -o wide --watch
```

#### Create MongoDB Deployment

Now create the  MongoDB deployment that will use the `mongo-storage` persistent volume claim to mount the directory that is to contain the MongoDB database files.

```
kubectl create -f deployments/mongo-deployment.yaml
```

Scale the deployment, since the deployment definition has replicas set to 0:

```
kubectl scale deploy/mongo --replicas=1
```

Verify the container has been created and is in the running state:

```
kubectl get pods -o wide --watch
```

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
kubectl create -f deployments/pacman-deployment.yaml
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

## Cleanup

#### Delete Kubernetes cluster

Delete the GKE cluster.

```
gcloud container --project "<YOUR_PROJECT_ID>" \
  clusters delete "kube-ref-app" --zone "us-central1-f"
```
