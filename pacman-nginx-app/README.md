# Pacman + NGINX + PHP + MongoDB Application

This is an example Kubernetes application that hosts an HTML5 Pacman game with NGINX as the web server and PHP backend to read and write data to a MongoDB database.

## Pacman Game Architecture Overview

### Pacman

The Pacman game is a slightly modified version of the open source Pacman game written in HTML5 with Javascript. You can get the modified
[Pacman game source code here](https://github.com/font/pacman-canvas).

### NGINX + PHP FPM

[NGINX](https://www.nginx.com/) is used as the web server to host the Pacman game application. It is configured with [PHP FPM](https://php-fpm.org/) support for the backend PHP API.

### PHP

PHP FPM is used for the PHP API to receive read and write requests from clients and perform database operations. The
[PHP MongoDB driver extension](http://php.net/manual/en/set.mongodb.php) contains the minimal API for core driver functionality. In addition, the
[PHP library for MongoDB](http://php.net/manual/en/mongodb.tutorial.library.php) provides the higher level APIs. Both are needed.

### MongoDB

[MongoDB](https://www.mongodb.com/) is used as the backend database to store the Pacman game's high score user data.

## Create Application Container Image

The [Dockerfile](Dockerfile) performs the following steps:

1. It is based on Ubuntu 16.04 Xenial and installs NGINX, PHP FPM, PHP MongoDB, and Composer (for the PHP MongoDB lib).
2. It then creates a basic NGINX configuration that includes enabling PHP FastCGI.
3. Clones the Pacman game into the configured root directory of the NGINX web server.
4. Replaces the host of 'localhost' with 'mongo' in the PHP backend API to match the host DNS given to the MongoDB Kubernetes service.
5. Exposes port 80 for the web server.
6. Starts `nginx`, `php7.0-fpm`, and runs a forever command to keep the container running.

To build the image run:

```
docker build -t <user>/pacman-nginx-app .
```

You can test the image by running:

```
docker run pacman-nginx-app
```

And going to `http://localhost/` to see if you get the Pacman game.

## Kubernetes Components

### Install Google Cloud SDK

To test on a Kubernetes cluster, make sure you have the [Google Cloud SDK installed](https://cloud.google.com/sdk/). You can quickly do this on Linux/Mac with:

```
curl https://sdk.cloud.google.com | bash
```

Once installed, log in and update it:

```
gcloud auth login
gcloud components update
```

### Create a Google Cloud Project

You can either create a new project or use an existing one. See the [Google Cloud Docs](https://cloud.google.com/resource-manager/docs/creating-managing-projects) for more details.

### Push container to Google Cloud Container Registry

You'll want to tag your previously created Docker image to use the Google Cloud Container Registry URL and then push it:

```
docker tag <user>/pacman-nginx-app gcr.io/<YOUR_PROJECT_ID>/pacman-nginx-app
gcloud docker push gcr.io/<YOUR_PROJECT_ID>/pacman-nginx-app
```

### Create the Kubernetes cluster

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

### Creating the MongoDB Service

#### Create a persistent disk to store the data

This allows us to not lose our data as pods come and go. To create the disk, run:

```
gcloud compute disks create \
  --project "<YOUR_PROJECT_ID>" \
  --zone "us-central1-f" \
  --size 200GB \
  mongo-disk
```

Be sure to use your project's ID and the zone that you selected for your cluster.

#### Create MongoDB replication controller

Now create the  MongoDB replication controller that will use the `gcePersistentDisk` volume plugin to mount
the `mongo-disk` we just created:

```
kubectl create -f mongo-controller.yaml
```

#### Create the MongoDB service

This component creates a mongo DNS entry, so this is why we use `mongo` as the host we connect to in our application instead of `localhost`.

```
kubectl create -f mongo-service.yaml
```

Verify the container has been created and is in the running state:

```
kubectl get pods -o wide --watch
```

### Creating the Web Application Server

We'll need to create the web server replication controller, this time with 2 replicas, and the service to access the application on port 80.

```
kubectl create -f web-controller.yaml
kubectl create -f web-service.yaml
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
