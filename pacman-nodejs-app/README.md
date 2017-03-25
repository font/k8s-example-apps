# Pac-Man + NodeJS + MongoDB Microservices Application

This is an example Kubernetes application that hosts an HTML5 Pac-Man game with Node.js as the web server and backend to read
and write data to a MongoDB database.

## Pac-Man Game Architecture Overview

### Pac-Man

The Pac-Man game is a modified version of the open source Pac-Man game written in HTML5 with Javascript. You can get the
modified [Pac-Man game source code here](https://github.com/font/pacman.git).

### Node.js

[Node.js](https://nodejs.org/) is used as the server side component to host the Pac-Man game application. It uses a few packages such as the
[Express](https://expressjs.com/) web application framework as well as the [MongoDB](https://mongodb.github.io/node-mongodb-native/) driver
for the backend Node.js API.

### MongoDB

[MongoDB](https://www.mongodb.com/) is used as the backend database to store the Pac-Man game's high score user data.

## Prerequisites

### Clone This Repository

Clone this repo which contains the Kubernetes configs and Dockerfile resources.

```
git clone https://github.com/font/k8s-example-apps.git
cd k8s-example-apps/pacman-nodejs-app
```

## Create Application Container Image

The [Dockerfile](docker/Dockerfile) performs the following steps:

1. It is based on Node.js LTS Version 6 (Boron).
2. It then clones the Pac-Man game into the configured application directory.
4. Replaces the host 'localhost' with 'mongo' in the Node.js MongoDB backend API to match the host DNS given to the MongoDB Kubernetes service.
5. Exposes port 80 for the web server.
6. Starts the Node.js application using `npm start`.

To build the image run:

```
cd docker
docker build -t <user>/pacman-nodejs-app .
cd ..
```

You can test the image by running:

```
docker run -p 8000:80 <user>/pacman-nodejs-app
```

And going to `http://localhost:8000/` to see if you get the Pac-Man game.

## Kubernetes Components

### Install Google Cloud SDK

To test on a Kubernetes cluster, make sure you have the [Google Cloud SDK installed](https://cloud.google.com/sdk/). You can quickly do this
on Linux/Mac with:

```
curl https://sdk.cloud.google.com | bash
```

Once installed, log in and update it:

```
gcloud auth login
gcloud components update
```

### Create a Google Cloud Project

You can either create a new project or use an existing one. See the
[Google Cloud Docs](https://cloud.google.com/resource-manager/docs/creating-managing-projects) for more details.

### Push container to Google Cloud Container Registry

You'll want to tag your previously created Docker image to use the Google Cloud Container Registry URL and then push it:

```
docker tag <user>/pacman-nodejs-app gcr.io/YOUR_PROJECT_ID/pacman-nodejs-app
gcloud docker push gcr.io/YOUR_PROJECT_ID/pacman-nodejs-app
```

Once you've pushed your image, you'll need to update the Kubernetes resources to point to your image before you continue
with the rest of the guides.

```
sed -i 's/ifontlabs/YOUR_PROJECT_ID/' controllers/web-controller.yaml replicasets/pacman-replicaset*.yaml
```

## Set Up Kubernetes Cluster(s)

You'll need to create 1 or at least 3 Kubernetes cluster(s) depending on whether you want to try out the Pac-Man app on 1 cluster,
or try it out on a federated cluster. Below are links to the two choices that will guide you through it:

- [Pac-Man Node.js App Single Cluster](docs/pacman-nodejs-app-single-cluster.md)
- [Pac-Man Node.js App Federated Cluster](docs/pacman-nodejs-app-federated-cluster.md)

## Scenarios

Follow the instructions in the below links to test out different federation scenarios.

1. [Add Kubernetes cluster to Federation and scale application onto it](docs/pacman-nodejs-app-federated-scenario-1.md).
2. Remove Kubernetes cluster from Federation and scale application to remaining clusters.
3. Destroy Kubernetes cluster and watch application scale to remaining clusters.
4. Perform scenarios 1-3 across public cloud providers e.g. GCP <-> AWS <-> Azure
