# Pac-Man Application On Federated Kubernetes Cluster With Multiple Public Cloud Provider Portability

This guide will walk you through creating multiple Kubernetes clusters spanning
multiple public cloud providers and use a federation control plane to deploy
the Pac-Man Node.js application onto each cluster, then move it away from AWS.
The Kubernetes clusters and Pac-Man application will be deployed using the
following public cloud providers: Google Cloud Platform, Amazon Web Services,
and Azure.

## High-Level Architecture

Below is a diagram demonstrating the architecture of the game across the federated kubernetes cluster after all the steps are completed.

![Pac-Man Game
Architecture](images/Kubernetes-Federation-Game-AWS-GKE-AZ-Portability.png)

## Prerequisites

#### Follow instructions for deploying Pac-Man on multiple cloud providers

You'll first need to deploy the federated control plane, then the Pac-Man
application so that you have a working Pac-Man game working across all three
cloud providers: AWS, GKE, and Azure. In order to do this, follow the
instructions at the following link up until you can play the game. Once
complete, return back here for the tutorial on migrating Pac-Man away from AWS.

- [Pac-Man application deployed on multiple public cloud providers in a federation: GKE, AWS, and Azure](pacman-nodejs-app-federated-multicloud.md)

## Migrate Pac-Man away from the AWS Kubernetes Cluster

Once you've played Pac-Man to verify your application has been properly
deployed, we'll migrate the application away from AWS to just the GKE and Azure
Kubernetes cluster only.

### Update DNS records

Before we can migrate the Pac-Man resources, we need to update the DNS to
reflect our desired topology so that we maintain uptime before we just remove
the AWS cluster.

Until the federation-v2 DNS load balancing feature is implemented, we need to
manually update the DNS entry to no longer point to the AWS cluster's `pacman`
federated service load balancer IP address. To do that, run the following
script:

```bash
./tools/dns/updatedns.sh -t gke-us-west1 -t az-us-central1 -n pacman \
    -z ${ZONE_NAME} -d ${DNS_NAME}
```

Once the script completes, you are ready to remove the Pac-Man resources from
the AWS cluster.

### Migrate Pac-Man Resources

Migrating the Pac-Man resources away from AWS is as simple as migrating the
`pacman` namespace. In order to do that, we need to modify the `pacman`
`federatednamespaceplacement` resource to specify that we no longer want AWS as
the cluster hosting the `pacman` namespace and all its contents. You can do
this via the following patch command or manually:

```bash
kubectl patch federatednamespaceplacement pacman -p \
    '{"spec":{"clusternames": ["gke-us-west1", "az-us-central1"]}}'
kubectl edit federatednamespaceplacement pacman
```

Wait until the pacman deployment no longer shows pods running in the AWS
cluster:

```bash
./bin/mckubectl get deploy pacman
```

## Play Pac-Man

Go ahead and play a few rounds of Pac-Man and invite your friends and
colleagues by giving them your FQDN to your Pac-Man application e.g.
[http://pacman.example.com/](http://pacman.example.com/) (replace
`example.com` with your DNS name).

The DNS will load balance (randomly) and resolve to any one of the zones in
your federated kubernetes cluster. This is represented by the `Cloud:` and
`Zone:` fields at the top, as well as the `Host:` Pod that it's running on.
When you save your score, it will automatically save these fields corresponding
to the instance you were playing on and display it in the High Score list.

See who can get the highest score!

## Cleanup

Follow the cleanup steps in [Pac-Man federated
multi-cloud](pacman-nodejs-app-federated-multicloud.md#cleanup).
