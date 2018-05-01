# Azure Kubernetes Tutorial

This tutorial will walk you through setting up a Kubernetes cluster on Azure using
[Azure Container Service (ACS)](https://azure.microsoft.com/en-us/services/container-service/).

## Prerequisites

#### Create Azure Account

You will need an [Azure account](https://azure.microsoft.com/en-us/free/) before proceeding.

#### Increase Quota

Make sure you increase your quota for the correct SKU in the specific region you will be creating your Kubernetes cluster.
For this example, we will be using the Central US region and the default
Azure Container Service (AKS) SKU `Standard_D1_v2`. We will also be using the
default master and agent node count of 1 and 3, respectively, for a total of 4
nodes.

You can check your current quota limit for the `Standard_Dv2` Family of SKUs in
the Central US location (what we'll use in our example below) using:

```bash
az vm list-usage --location "Central US" --query "[?name.value=='standardDv2Family']"
```

If you do not have sufficient quota for the Dv2 Series of SKUs in the Central US region, you will receive
a `QuotaExceeded` error. You can read more about this error on
[Azure's Resource Management Common Deployment Errors](https://docs.microsoft.com/en-us/azure/azure-resource-manager/resource-manager-common-deployment-errors#quotaexceeded).
If you are using the free trial of Azure, or do not have at least 4 CPU cores
available (1 vCPU core per node * 4 nodes), then file a request using the
[Azure
Portal](https://portal.azure.com/?#blade/Microsoft_Azure_Support/HelpAndSupportBlade).

Alternatively, you can modify the cluster create command to specify a different SKU for which you do have enough quota.

## Set Up Azure Command Line Interface

#### Install Azure CLI

Follow [these instructions](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) to install Azure CLI on your OS.

To verify the installation was successful:

```bash
az --version
```

#### Log in to Azure

Once the Azure CLI is installed, connect to your Azure account using the below command and follow the instructions outputted.
See [here](https://docs.microsoft.com/en-us/cli/azure/get-started-with-azure-cli#log-in-to-azure) for more details.

```bash
az login
```

## Create Kubernetes Cluster

There are two ways to create a Kubernetes cluster using Azure's Container Service:

1. Using the default `az aks create` command. This option is not as flexible
   but easier to set up. For example, you cannot currently specify any version
   of Kubernetes you would like to use in the deployment using this option.
2. Using Azure's Container Service Engine. This option provides the most
   flexibility to create a custom Kubernetes cluster, but is not as trivial to
   set up.  You will need to use this example if you are looking to use a
   specific version of Kubernetes that is not currently supported by option 1.

#### Create Resource Group

Before you can create a cluster regardless of the options above, you need to create a resource group in a specific geo location if you don't already have one.
Run these example commands to use the Central US region while specifying whatever name you'd like for the `RESOURCE_GROUP`.

```bash
RESOURCE_GROUP=my-resource-group
LOCATION=centralus
az group create --name=${RESOURCE_GROUP} --location=${LOCATION}
```

### Option 1

This will go over the steps required to build a Kubernetes cluster using Azure's Container Service by utilizing the `az aks create` command.
The difference is that this option does not allow specifying certain
parameters, such as the version of Kubernetes you would like to use beyond
what's supported by AKS.

We will essentially be following [these official steps from Azure's online
container service
documentation](https://docs.microsoft.com/en-us/azure/aks/kubernetes-walkthrough).

#### Enable AKS Preview

While AKS is in preview, creating new clusters requires a feature flag on your
subscription. You may request this feature for any number of subscriptions that
you would like to use. Use the az provider register command to register the AKS
provider:

```bash
az provider register -n Microsoft.Network
az provider register -n Microsoft.Storage
az provider register -n Microsoft.Compute
az provider register -n Microsoft.ContainerService
```

#### Create Cluster

To see a list of available AKS versions run:

```bash
az aks get-versions -l ${LOCATION}
```

Once you have a resource group, you are ready to create a cluster in that group. Run the command below. Feel free to use
whatever `DNS_PREFIX` and `AZ_CLUSTER_NAME` you prefer.

NOTE: This command also automatically generates the
[Azure Active Directory service principal](https://docs.microsoft.com/en-us/azure/container-service/container-service-kubernetes-service-principal)
that a Kubernetes cluster in Azure uses and will generate SSH public and private key pairs if you don't already have them.

```bash
DNS_PREFIX=az-us-central1
AZ_CLUSTER_NAME=az-us-central1
az aks create \
    --resource-group ${RESOURCE_GROUP} \
    --name=${AZ_CLUSTER_NAME} \
    --dns-name-prefix=${DNS_PREFIX} \
    --kubernetes-version 1.9.6 \
    --generate-ssh-keys \
    --verbose
```

#### Connect to the Cluster

Make sure you have [`kubectl`](https://kubernetes.io/docs/tasks/kubectl/install/) already installed, then run the below command to download
the master Kubernetes cluster configuration to the `~/.kube/config` file:

```bash
az aks get-credentials --resource-group=${RESOURCE_GROUP} --name=${AZ_CLUSTER_NAME}
```

#### Verify the Cluster

You should now be able to access your cluster using:

```bash
kubectl get nodes -o wide
```

Verify you can see all the machines in your cluster.

### Option 2

This will go over the steps required to build a Kubernetes cluster using [Azure's Container Service Engine](https://github.com/Azure/acs-engine).
The ACS Engine is the open source tool used by Micrsoft Azure to drive Azure Container Service. It generates Azure Resource Manager (ARM) templates
for Docker enabled clusters on Microsoft Azure with your choice of container orchestration tool to use. We'll be utilizing Kubernetes for our setup.

The difference from option 1 is that this tool provides much more flexibility to customize the Kubernetes cluster e.g. the Kubernetes version you'd like to use.
This guide will essentially walk you through [these official steps](https://github.com/Azure/acs-engine/blob/master/docs/kubernetes.md#deployment) to get set up.

The `acs-engine` tool will take a cluster definition in JSON as input and outputs several generated JSON configuration files.
These generated configuration files are then passed as arguments to the `az group deployment create` command.

#### Install acs-engine

There are two ways to get the `acs-engine` tool as described
[here](https://github.com/Azure/acs-engine/blob/master/docs/acsengine.md#install).

1. [Binary downloads](https://github.com/Azure/acs-engine/releases/latest).
   This method is the quickest and most stable.
2. [Building ACS Engine from
   source](https://github.com/Azure/acs-engine/blob/master/docs/acsengine.md#build-acs-engine-from-source).
   This requires a little more setup initially in order to get golang
   installed, but once it is set up it's quick and easy to use afterwards.

#### Export DNS Prefix

We'll export a variable used for this section.

```bash
DNS_PREFIX=az-us-central1
```

#### SSH Key Generation

Follow [these instructions](https://github.com/Azure/acs-engine/blob/master/docs/ssh.md#ssh-key-generation) for your OS to set up
an SSH RSA key if you do not have one already.

#### Create Azure Service Account

You'll need to create a Service Account that the `acs-engine` tool can use to perform actions on your behalf. This is done via
[Active Directory Service Principals](https://docs.microsoft.com/en-us/azure/active-directory/develop/active-directory-application-objects).

First, you'll need your Azure `SUBSCRIPTION_ID` which you can get by executing the below command assuming the first account (0)
is the account you're working from:

```bash
SUBSCRIPTION_ID=$(az account list --query [0].id)
```

Then, follow [these instructions](https://github.com/Azure/acs-engine/blob/master/docs/serviceprincipal.md#creating-a-service-principal)
in order to create a Service Principal in Azure Active Directory. If you followed steps to test the new Service Principal by logging in
using the new account, don't forget to log back into your main account by following the instructions via:

```bash
az login
```

Also, if you get strange `az login` parsing type errors, try executing this first:

```bash
az account clear
```

If you already have a Service Principal in Azure Active Directory, but forgot your name/appId or password, then try to query it to retrieve
the name/appId:

```bash
APP_ID=$(az ad sp list --display-name 'azure-cli' --query [0].appId)
```

If you forgot the password or did not write it down from when you previously created the Service Principal, then reset the password to an
auto-generated one using:

```bash
az ad sp reset-credentials --name ${APP_ID}
```

#### Edit Kubernetes Cluster Template

Next, you need to edit the [Kubernetes cluster example template](https://github.com/Azure/acs-engine/blob/master/examples/kubernetes.json) in your
development environment. For that you can either download the file directly from the link above, clone the repo, or if you used the method to
build `acs-engine` locally from source you have already downloaded the repo source code.

In the `kubernetes.json` file, you'll need to add a few things:

1. Change the `dnsPrefix` value to something unique such as the value of the
   environment variable `DNS_PREFIX` since we'll be building a cluster in the central region.
2. Add the contents of your SSH `id_rsa.pub` public key to the value of the `keyData` field.
3. Add the `appId` from the Service Principal account you created above to the
   `clientId` value within the `servicePrincipalProfile` object variable.
4. Add the `password` from the Service Principal account you created above to
   the `secret` value within the `servicePrincipalProfile` object variable.

That's all we'll be using but see [here](https://github.com/Azure/acs-engine/blob/master/docs/clusterdefinition.md)
for a complete list of cluster definitions.

#### Generate Kubernetes Cluster Configuration

Once your Kubernetes cluster template contains the necessary field values, you can generate the Kubernetes cluster configuration by executing:

```bash
acs-engine generate examples/kubernetes.json
```

This will generate the configurations in the `_output/${DNS_PREFIX}` directory.
This `DNS_PREFIX` is just the value you specified in the
`kubernetes.json` template.

The two important configuration files are the
`_output/${DNS_PREFIX}/azuredeploy.json` and `_output/${DNS_PREFIX}/azuredeploy.parameters.json`
for deployment.

#### Modify Kubernetes Cluster Configuration

You can now modify any of the parameters in the `azuredeploy.json` and `azuredeploy.parameters.json` configuration before deployment.

Specifically, you can modify the version of Kubernetes used. For this you'll want to edit the `kubernetesHyperkubeSpec` value field in the
`_output/${DNS_PREFIX}/azuredeploy.parameters.json` config file to contain a link to the version of Kubernetes you want to use.
This can be any custom version of Kubernetes, or an official release. For example, to use
an official release of Kubernetes 1.8.4, modify the field to contain:

```json
  "kubernetesHyperkubeSpec": {
    "defaultValue": "gcrio.azureedge.net/google_containers/hyperkube-amd64:v1.8.4"
  },
```

#### Deploy Kubernetes Cluster

You're now ready to deploy your Kubernetes cluster. Execute the following example command.

**Make sure to include the '@' in the `--parameters` option**

```bash
az group deployment create --name "${DNS_PREFIX}" \
    --resource-group "${RESOURCE_GROUP}" \
    --template-file "./_output/${DNS_PREFIX}/azuredeploy.json" \
    --parameters "@./_output/${DNS_PREFIX}/azuredeploy.parameters.json" \
    --verbose
```

#### Verify the Cluster

In order to verify the cluster for this method of deployment, we need to download the kubeconfig file from the master node and
then tell `kubectl` to merge it with the default kubeconfig file by exporting the `KUBECONFIG` environment variable. Then we
can use `kubectl` to check on our cluster.

```bash
MASTER_IP=$(az network public-ip list --query "[?contains(name,'k8s-master')].ipAddress | [0]" | sed 's/"//g')
scp azureuser@${MASTER_IP}:.kube/config .
export KUBECONFIG=~/.kube/config:`pwd`/config
kubectl config use-context ${DNS_PREFIX}
kubectl get nodes -o wide
```

## Cleanup

Cleanup can be performed by deleting the resource group:

```bash
az group delete --name=${RESOURCE_GROUP} --verbose
```
