# AWS Kubernetes Tutorial

This tutorial will walk you through setting up a Kubernetes cluster on AWS using [kops](https://github.com/kubernetes/kops), a tool
to automate the creation and deployment of a production grade Kubernetes cluster.

## Installing kops

Follow [these instructions](https://github.com/kubernetes/kops#installing) to install kops on your client.

## Setup Your AWS Environment

#### Install and Configure AWS CLI

Before you can start using the AWS CLI, you need an AWS acount. Follow
[these steps](http://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-set-up.html#cli-signup) if you don't already have one.

Once you have an AWS account, you'll need to install and configure the AWS CLI:

1. First, make sure you have an access key ID and secret access key.
   [See here for instructions](http://docs.aws.amazon.com/cli/latest/userguide/cli-chap-getting-set-up.html#cli-signup) on getting your access key ID and secret access key.
2. Follow the [official AWS Command Line Interface tools installation instructions](http://docs.aws.amazon.com/cli/latest/userguide/installing.html) for your OS.
3. Use `aws configure` to configure `aws` to use your access key ID, secret access key, and setup to use the `us-east-1` region.
   Feel free to specify any output format you like, e.g. `json`.

#### Setup IAM User

You'll need a dedicated IAM user for `kops` to build clusters within AWS. The `kops` user requires a certain set
of IAM permissions to function. You'll also need to export the `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`. Follow these instructions in
the `kops` repo to get setup:

https://github.com/kubernetes/kops/blob/master/docs/aws.md#setup-iam-user

## Configure DNS

The `kops` tool requires a place to build the necessary DNS records in order to build a Kubernetes cluster. There are several scenarios
available that you can choose from. You can read about all the different scenarios here:

https://github.com/kubernetes/kops/blob/master/docs/aws.md#configure-dns

For this particular case, I have been using Google's Cloud DNS configuration with a custom subdomain. This is
[Scenario 3](https://github.com/kubernetes/kops/blob/master/docs/aws.md#scenario-3-subdomain-for-clusters-in-route53-leaving-the-domain-at-another-registrar)
in the above link. This basically involves installing [`jq`](https://github.com/stedolan/jq/wiki/Installation) and then running the below command
replacing `subdomain.example.com` with your chosen *subdomain*. This same *subdomain* will be used later as part of the cluster name.

```
ID=$(uuidgen) && aws route53 create-hosted-zone --name subdomain.example.com --caller-reference $ID | jq .DelegationSet.NameServers

```

You then take the 4 NS records received from the above command and create a new **subdomain** NS record type within your Google DNS Managed Zone
consisting of these 4 name servers.

You will need to follow similar steps for other registrars.

**Make sure to test your DNS setup by following [these instructions](https://github.com/kubernetes/kops/blob/master/docs/aws.md#testing-your-dns-setup) before moving on.**

## Cluster State Storage

We need to create a dedicated S3 bucket for `kops` to manage the state of your cluster. [See here for details](https://github.com/kubernetes/kops/blob/master/docs/aws.md#cluster-state-storage).

## Create the Kubernetes Cluster

#### Setup Environment Variables

To make this process easier, let's setup a couple environment variables to facilitate copying and pasting from this guide.

Since we used a **SUBDOMAIN** for our DNS configuration above, we will re-use the name below. That is, the `AWS_CLUSTER_NAME` needs to contain
the same **SUBDOMAIN** value used in the `aws route53 create-hosted-zone --name subdomain.example.com` command above so replace `subdomain.example.com`
with your subdomain.

The `KOPS_STATE_STORE` variable will be automatically picked up by `kops` so we do not need to continually specify it using
the `--state` parameters.

```bash
export AWS_CLUSTER_NAME=us-east-1.subdomain.example.com
export KOPS_STATE_STORE=s3://prefix-example-com-state-store
```

#### Create Cluster Configuration

We need to specify a zone for the cluster. For this, we need to know which availability zones are available to us.
For this example we will be deploying our cluster to the us-east-1b region.

```
aws ec2 describe-availability-zones --region us-east-1
```

Create the cluster configuration using the example command below. This only creates the cluster configuration but does not start building it.

```
kops create cluster --name ${AWS_CLUSTER_NAME} \
    --zones us-east-1b \
    --kubernetes-version 1.9.6
```

There are several other options you can specify e.g. `--node-count`, `--node-size`, `--master-size`, etc.
See the [list of commands](https://github.com/kubernetes/kops/blob/master/docs/commands.md#other-interesting-modes) for more information.

#### Edit Cluster Configuration

Now that we have a cluster configuration, we can modify any of its details using the edit command below that will open your editor defined by
the `EDITOR` environment variable. The configuration is read and automatically saved to the S3 bucket we created earlier when you save and exit
the editor.

```
kops edit cluster --name ${AWS_CLUSTER_NAME}
```

#### Build the Cluster

Now we're ready to build the cluster. This will take a while and once it's complete, you'll still have to wait longer while the booted instances
finish downloading the Kubernetes components and reach a ready state. The `--yes` option is required to actually build the cluster, otherwise `kops`
will dump a list of cloud resources it will create without applying any changes.

```
kops update cluster --name ${AWS_CLUSTER_NAME} --yes
```

#### Verify the Cluster

`kops` will automatically update your `kubectl` config with the context details to connect to your cluster. Verify the cluster
using:

```
kubectl get nodes
kubectl --namespace kube-system get all -o wide
```

`kops` also has a command to validate the cluster is working correctly:

```
kops validate cluster --name ${AWS_CLUSTER_NAME}
```

## Cleanup

Cleanup is rather easy by running the below commands. You may want to run the `kops delete cluster` command first
without the `--yes` option to preview the changes before committing them.

### Delete Cluster

```
kops delete cluster --name ${AWS_CLUSTER_NAME} --yes
```

### Delete S3 Bucket

```
aws s3api delete-bucket --bucket prefix-example-com-state-store
```
