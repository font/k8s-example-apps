# Pac-Man Application On Federated Kubernetes Cluster With Multiple Public Cloud Provider Portability

This guide will walk you through creating multiple Kubernetes clusters spanning
multiple public cloud providers and use a federation control plane to deploy
the Pac-Man Node.js application onto the Google Cloud Platform and Microsoft
Azure clusters, then swap the Amazon Web Services cluster with the Azure
cluster.

## High-Level Architecture

Below are diagrams demonstrating the architecture of the game across the
federated kubernetes cluster as you complete each step.

Initial setup contains GCP and Azure:

![Pac-Man Game
Architecture](images/Kubernetes-Federation-Game-AWS-GKE-AZ-Portability.png)

Next, we add AWS:

![Pac-Man Game
Architecture](images/Kubernetes-Federation-Game-AWS-GKE-AZ.png)

Then we remove Azure:

![Pac-Man Game
Architecture](images/Kubernetes-Federation-Game-GKE-AZ-AWS-Portability.png)

## Prerequisites

#### Follow instructions for deploying Pac-Man on multiple cloud providers and migrating Pac-Man away from AWS.

You'll first need to deploy the federated control plane, then the Pac-Man
application, then migrate away from AWS so that you have a working Pac-Man game
working across both cloud providers: GKE and Azure. In order to do this, follow the
instructions at the following link up until you can play the game. Once
complete, return back here for the tutorial on swapping AWS with Azure i.e. scaling out to AWS, then
migrating away from Azure.

- [Pac-Man application portability: deploy on AWS, GKE, and Azure, then move
  away from AWS](pacman-nodejs-app-federated-aws-gke-az-portability.md)

## Migrate Pac-Man from Azure to the AWS Kubernetes Cluster

Once you've played Pac-Man to verify your application has been properly
deployed and running on GKE and Azure, we'll migrate the application from Azure to AWS so
that we have Pac-Man running on the GKE and AWS Kubernetes clusters.

### Scale Pac-Man Resources

First, we need to scale the Pac-Man resources to AWS. It is as simple as
scaling the `pacman` namespace. In order to do that, we need to modify the
`pacman` `federatednamespaceplacement` resource to specify that we now want AWS
as another cluster hosting the `pacman` namespace and all its contents. You can
do this via the following patch command or manually:

```bash
kubectl patch federatednamespaceplacement pacman --type=merge -p \
    '{"spec":{"clusterNames": ["gke-us-west1", "az-us-central1", "aws-us-east1"]}}'
kubectl edit federatednamespaceplacement pacman
```

Wait until the pacman deployment shows pods running in the AWS cluster:

```bash
./tools/mckubectl/mckubectl get deploy pacman
```

Once the pacman deployment shows pods running in the AWS cluster, you can
proceed to updating the DNS record.

### Update DNS

This section is broken up into different methods of updating DNS, depending on
what method you chose during the tutorials.

#### Manually

If you used the manual DNS setup during the tutorial, you'll want to use this
section for migrating.

Now that we have Pac-Man resources in our AWS cluster, we need to update the
DNS to reflect our desired topology so that we can complete the next step of
the migration of Pac-Man to the AWS cluster. We will remove the Azure cluster
from the DNS before we migrate the Pac-Man resources away from Azure so that we
maintain uptime.

We need to manually update the DNS entry to also point to the AWS cluster's
`pacman` federated service load balancer IP address. To do that, run the
following script:

```bash
./tools/dns/updatedns.sh -t gke-us-west1 -t aws-us-east1 -n pacman \
    -z ${ZONE_NAME} -d ${DNS_NAME}
```

Once the script completes, the DNS will be updated to point to the GKE and AWS
clusters.

#### ExternalDNS

If you used `external-dns` to set up DNS during the tutorial, rest assured
that as you continue through this section your DNS will be automatically
updated by `external-dns`.

### Migrate Pac-Man Resources

Migrating the Pac-Man resources away from Azure is as simple as migrating the
`pacman` namespace. In order to do that, we need to modify the `pacman`
`federatednamespaceplacement` resource to specify that we no longer want Azure as
the cluster hosting the `pacman` namespace and all its contents. You can do
this via the following patch command or manually:

```bash
kubectl patch federatednamespaceplacement pacman --type=merge -p \
    '{"spec":{"clusterNames": ["gke-us-west1", "aws-us-east1"]}}'
kubectl edit federatednamespaceplacement pacman
```

Wait until the pacman deployment no longer shows pods running in the Azure
cluster:

```bash
./tools/mckubectl/mckubectl get deploy pacman
```

Once that's done, the migration is complete and you are ready to play to verify
your changes.

## Play Pac-Man

Go ahead and play a few rounds of Pac-Man and invite your friends and
colleagues by giving them your FQDN to your Pac-Man application e.g.
[http://pacman.example.com/](http://pacman.example.com/) (replace
`example.com` with your DNS name).

The DNS will load balance (randomly) and resolve to any one of the zones in
your federated kubernetes cluster. This is represented by the `Cloud:` and
`Zone:` fields at the top, as well as the `Host:` Pod that it's running on.
When you save your score, it will automatically save these fields corresponding
to the instance you were playing on and display it in the High Score list. When
you view the High Score list, you will notice that all the previous high scores
are still there!

See who can get the highest score!

## Cleanup

Follow the cleanup steps in [Pac-Man federated
multi-cloud](pacman-nodejs-app-federated-multicloud.md#cleanup).
