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
Kubernetes clusters only.

### Update Load Balancer

Here we'll update the load balancer using DNS or an L7 load balancer, depending
on what method you chose during the tutorials. Follow the instructions below
for the method you used.

#### Update DNS

This section is broken up into different methods of updating DNS, depending on
what DNS method you chose during the tutorials.

##### Manually

If you used the manual DNS setup during the tutorial, you'll want to use this
section for migrating.

Before we can migrate the Pac-Man resources, we need to update the DNS to
reflect our desired topology so that we maintain uptime before we just remove
the AWS cluster.

We need to manually update the DNS entry to no longer point to the AWS
cluster's `pacman` federated service load balancer IP address. To do that, run
the following script:

```bash
./tools/dns/updatedns.sh -t gke-us-west1 -t az-us-central1 -n pacman \
    -z ${ZONE_NAME} -d ${DNS_NAME}
```

Once the script completes, you are ready to remove the Pac-Man resources from
the AWS cluster.

##### ExternalDNS

If you used `external-dns` to set up DNS during the tutorial, rest assured
that as you continue through this section your DNS will be automatically
updated by `external-dns`.

#### L7 Load Balancer

This section covers updating the L7 load balancer used during the setup of the
game.

##### HAProxy

In order to remove the AWS cluster load balancer IP address, we should update
the HAProxy config using the Runtime API. Note that you could avoid removing
the AWS load balancer server from the HAProxy config and when the Pac-Man
resources are moved from AWS, the health check would automatically disable the
server anyway. Here we'll choose to update HAProxy for completeness.

Run the following script to automate updating the L7 load balancer:

```bash
./tools/lb/updatelb.sh -t gke-us-west1 -t az-us-central1 -n pacman
```

Once the script completes, the L7 load balancer will be updated to load balance
traffic between the GKE and Azure clusters.

### Migrate Pac-Man Resources

Migrating the Pac-Man resources away from AWS is as simple as migrating the
`pacman` namespace. In order to do that, we need to modify the `pacman`
`federatednamespaceplacement` resource to specify that we no longer want AWS as
the cluster hosting the `pacman` namespace and all its contents. You can do
this via the following patch command or manually:

```bash
kubectl patch federatednamespaceplacement pacman --type=merge -p \
    '{"spec":{"clusterNames": ["gke-us-west1", "az-us-central1"]}}'
kubectl edit federatednamespaceplacement pacman
```

Wait until the pacman deployment no longer shows pods running in the AWS
cluster:

```bash
./tools/mckubectl/mckubectl get pods
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
