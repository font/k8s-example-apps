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

### Create Application Container Image

The [Dockerfile](docker/Dockerfile) performs the following steps:

1. It is based on Node.js LTS Version 6 (Boron).
1. It then clones the Pac-Man game into the configured application directory.
1. Exposes port 8080 for the web server.
1. Starts the Node.js application using `npm start`.

To build the image run:

```
cd docker
docker build -t <user>/pacman-nodejs-app .
cd ..
```

You can test the image by running:

```
docker run -p 8000:8080 <user>/pacman-nodejs-app
```

And going to `http://localhost:8000/` to see if you get the Pac-Man game.

### Container Registry

#### Create a Quay Account

Create a [Quay](https://quay.io/) account which allows unlimited storage and serving of public
repositories.

#### Sign Into Your Quay Account

Run the following `docker` command to sign in:

```bash
$ docker login quay.io
Username: myusername
Password: mypassword
```

#### Push Container Image to Quay

You'll want to tag your previously created Docker image to use the  URL and then push it:

```
docker tag <user>/pacman-nodejs-app quay.io/YOUR_USERNAME/pacman-nodejs-app
docker push quay.io/YOUR_USERNAME/pacman-nodejs-app
```

Once you've pushed your image, you'll need to update the Kubernetes resources
to point to your image before you continue with the rest of the guides.

```
sed -i 's/ifont/YOUR_USERNAME/' deployments/pacman-deployment*.yaml
```

#### Make Container Image Public

Go the `settings` tab for your repository and modify the `Repository Visibilty`
to make the repository public. To navigate directly there, replace `<username>`
with your username:
https://quay.io/repository/<username>/pacman-nodejs-app?tab=settings

Afer pushing, make sure to make your repository public on `quay.io`.


## Kubernetes Cluster Use-Cases

You'll need to create 1 to at least 3 Kubernetes cluster(s) depending on whether you want to try out the Pac-Man app on 1 cluster,
or try it out on multiple clusters. Below are links that will guide you through it.

### Single Kubernetes Cluster

- [Pac-Man Node.js App Single Cluster](docs/pacman-nodejs-app-single-cluster.md)

### Federated-v2 Kubernetes Cluster Use-Cases

Follow the instructions in the below links to test out different federation use-cases.

- [Pac-Man application deployed on GKE k8s federated cluster](docs/pacman-nodejs-app-federated-gke.md)
- [Pac-Man application deployed on multiple public cloud providers in a federation: GKE, AWS, and Azure](docs/pacman-nodejs-app-federated-multicloud.md)
- [Pac-Man application portability: deploy on AWS, GKE, and Azure, then move
  away from AWS](docs/pacman-nodejs-app-federated-aws-gke-az-portability.md)
- [Pac-Man application portability: deploy on GKE and Azure, then swap Azure
  with AWS](docs/pacman-nodejs-app-federated-gke-az-aws-portability.md)

### Kubernetes Cluster Use-Cases (Without Federation)

- [Pac-Man application migration using GKE](docs/pacman-nodejs-app-gke-migration.md)
- [Pac-Man application migration from AWS to GKE](docs/pacman-nodejs-app-aws-gke-migration.md)
