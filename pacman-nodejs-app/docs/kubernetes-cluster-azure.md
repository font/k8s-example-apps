# Azure Kubernetes Tutorial

This tutorial will walk you through setting up a Kubernetes cluster on Azure using
[Azure Container Service (ACS)](https://azure.microsoft.com/en-us/services/container-service/).

## Prerequisites

#### Create Azure Account

You will need an [Azure account](https://azure.microsoft.com/en-us/free/) before proceeding.

#### Increase Quota

Make sure you increase your quota for the correct SKU in the specific region you will be creating your Kubernetes cluster.
For this example, we will be using the West Central US region and the default Azure Container Service SKU `Standard_D2_v2`.
We will also be using the default master and agent node count of 1 and 3, respectively, for a total of 4 nodes.

You can check your current quota limit for the `Standard_D2_v2` SKU in the West Central US
location (what we'll use in our example below) using:

```
az vm list-usage --location "West Central US" --query "[?name.value=='standardDv2Family']"
```

If you do not have sufficient quota for the Dv2 Series of SKUs in the West Central US region, you will receive
a `QuotaExceeded` error. You can read more about this error on
[Azure's Resource Management Common Deployment Errors](https://docs.microsoft.com/en-us/azure/azure-resource-manager/resource-manager-common-deployment-errors#quotaexceeded).
If you are using the free trial of Azure, or do not have at least 8 CPU cores available (2 CPU cores per node * 4 nodes), then
file a request using the [Azure Portal](https://portal.azure.com/?#blade/Microsoft_Azure_Support/HelpAndSupportBlade).

Alternatively, you can modify the cluster create command to specify a different SKU for which you do have enough quota.

## Set Up Azure Command Line Interface

#### Install Azure CLI

Follow [these instructions](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) to install Azure CLI on your OS.

To verify the installation was successful:

```
az --version
```

#### Log in to Azure

Once the Azure CLI is installed, connect to your Azure account using the below command and follow the instructions outputted.
See [here](https://docs.microsoft.com/en-us/cli/azure/get-started-with-azure-cli#log-in-to-azure) for more details.

```
az login
```

## Create Kubernetes Cluster

There are two ways to create a Kubernetes cluster using Azure's Container Service:

1. Using the default `az acs create` command. This option is not as flexible but easier to set up. For example, you cannot currently specify the version
   of Kubernetes you would like to use in the deployment using this option.
2. Using Azure's Container Service Engine. This option provides the most flexibility but is not as trivial to set up. You will need to use this example
   if you are looking to use a specific version of Kubernetes that is not currently supported by option 1.

#### Create Resource Group

Before you can create a cluster regardless of the options above, you need to create a resource group in a specific geo location if you don't already have one.
Run these example commands to use the West Central US region while specifying whatever name you'd like for the `RESOURCE_GROUP`.

```
RESOURCE_GROUP=my-resource-group
LOCATION=westcentralus
az group create --name=${RESOURCE_GROUP} --location=${LOCATION}
```

### Option 1

This will go over the steps required to build a Kubernetes cluster using Azure's Container Service by utilizing the `az acs create` command.
The difference is that this option does not allow specifying certain parameters, such as the version of Kubernetes you would like to use.
So we will essentially be following
[these official steps from Azure's online container service documentation](https://docs.microsoft.com/en-us/azure/container-service/container-service-kubernetes-walkthrough).


#### Create Cluster

Once you have a resource group, you are ready to create a cluster in that group. Run the command below. Feel free to use
whatever `DNS_PREFIX` and `CLUSTER_NAME` you prefer.

NOTE: This command also automatically generates the
[Azure Active Directory service principal](https://docs.microsoft.com/en-us/azure/container-service/container-service-kubernetes-service-principal)
that a Kubernetes cluster in Azure uses and will generate SSH public and private key pairs if you don't already have them.

```
DNS_PREFIX=az-us-central1
CLUSTER_NAME=az-us-central1
az acs create --orchestrator-type=kubernetes \
    --resource-group ${RESOURCE_GROUP} \
    --name=${CLUSTER_NAME} \
    --dns-prefix=${DNS_PREFIX} \
    --generate-ssh-keys \
    --verbose
```

#### Connect to the Cluster

Make sure you have [`kubectl`](https://kubernetes.io/docs/tasks/kubectl/install/) already installed, then run the below command to download
the master Kubernetes cluster configuration to the `~/.kube/config` file:

```
az acs kubernetes get-credentials --resource-group=${RESOURCE_GROUP} --name=${CLUSTER_NAME}
```

#### Verify the Cluster

You should now be able to access your cluster using:

```
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

There are two ways to get the `acs-engine` tool as described [here](https://github.com/Azure/acs-engine/blob/master/docs/acsengine.md).

1. [Development in Docker](https://github.com/Azure/acs-engine/blob/master/docs/acsengine.md#development-in-docker). This method is
   likely the quickest as the build tools are in the container image.
2. [Building ACS Engine Locally](https://github.com/Azure/acs-engine/blob/master/docs/acsengine.md#downloading-and-building-acs-engine-locally).
   This requires a little more setup initially in order to get golang installed, but once it is set up it's quicker and easier to use afterwards.

#### SSH Key Generation

Follow [these instructions](https://github.com/Azure/acs-engine/blob/master/docs/ssh.md#ssh-key-generation) for your OS to set up
an SSH RSA key if you do not have one already.

#### Create Azure Service Account

You'll need to create a Service Account that the `acs-engine` tool can use to perform actions on your behalf. This is done via
[Active Directory Service Principals](https://docs.microsoft.com/en-us/azure/active-directory/develop/active-directory-application-objects).

First, you'll need your Azure `SUBSCRIPTION_ID` which you can get by executing the below command assuming the first account (0)
is the account you're working from:

```
SUBSCRIPTION_ID=$(az account list --query [0].id)
```

Then, follow [these instructions](https://github.com/Azure/acs-engine/blob/master/docs/serviceprincipal.md#creating-a-service-principal)
in order to create a Service Principal in Azure Active Directory. If you followed steps to test the new Service Principal by logging in
using the new account, don't forget to log back into your main account by following the instructions via:

```
az login
```

Also, if you get strange `az login` parsing type errors, try executing this first:

```
az account clear
```

If you already have a Service Principal in Azure Active Directory, but forgot your name/appId or password, then try to query it to retrieve
the name/appId:

```
APP_ID=$(az ad sp list --display-name 'azure-cli' --query [0].appId)
```

If you forgot the password or did not write it down from when you previously created the Service Principal, then reset the password to an
auto-generated one using:

```
az ad sp reset-credentials --name ${APP_ID}
```

#### Edit Kubernetes Cluster Template

Next, you need to edit the [Kubernetes cluster example template](https://github.com/Azure/acs-engine/blob/master/examples/kubernetes.json) in your
development environment. For that you can either download the file directly from the link above, clone the repo, or if you used the method to
build `acs-engine` locally from source you have already downloaded the repo source code.

In the `kubernetes.json` file, you'll need to add a few things:

1. Change the `dnsPrefix` value to something unique such as `az-us-central1` since we'll be building a cluster in the central region.
2. Add the contents of your SSH `id_rsa.pub` public key to the value of the `keyData` field.
3. Add the `appId` from the Service Principal account you created above to the `servicePrincipalClientID` value.
4. Add the `password` from the Service Principal account you created above to the `servicePrincipalClientSecret` value.

That's all we'll be using but see [here](https://github.com/Azure/acs-engine/blob/master/docs/clusterdefinition.md)
for a complete list of cluster definitions.

#### Generate Kubernetes Cluster Configuration

Once your Kubernetes cluster template contains the necessary field values, you can generate the Kubernetes cluster configuration by executing:

```
acs-engine examples/kubernetes.json
```

This will generate the configurations in the `_output/Kubernetes-UNIQUEID` directory. The `UNIQUEID` is just a hash of your master's FQDN prefix containing
the `dnsPrefix` you specified.

The two important configuration files are the `_output/Kubernetes-UNIQUEID/azuredeploy.json` and `_output/Kubernetes-UNIQUEID/azuredeploy.parameters.json`
for deployment.

#### Modify Kubernetes Cluster Configuration

You can now modify any of the parameters in the `azuredeploy.json` and `azuredeploy.parameters.json` configuration before deployment.

Specifically, you can modify the version of Kubernetes used. For this you'll want to edit the `kubernetesHyperkubeSpec` value field in the
`_output/Kubernetes-UNIQUEID/azuredeploy.parameters.json` config file to contain a link to the version of Kubernetes you want to use.
This can be any custom version of Kubernetes, or an official release. For example, to use
an official release of Kubernetes 1.5.6, modify the field to contain:

```
  "kubernetesHyperkubeSpec": {
    "value": "gcrio.azureedge.net/google_containers/hyperkube-amd64:v1.5.6"
  },
```

#### Deploy Kubernetes Cluster

You're now ready to deploy your Kubernetes cluster. Execute the following example command.

**Make sure to include the '@' in the `--parameters` option**

```
az group deployment create --name "az-us-central1" \
    --resource-group "${RESOURCE_GROUP}" \
    --template-file "./_output/<INSTANCE>/azuredeploy.json" \
    --parameters "@./_output/<INSTANCE>/azuredeploy.parameters.json" \
    --verbose
```

#### Verify the Cluster

In order to verify the cluster for this method of deployment, we need to download the kubeconfig file from the master node and
then tell `kubectl` to merge it with the default kubeconfig file by exporting the `KUBECONFIG` environment variable. Then we
can use `kubectl` to check on our cluster.

```
MASTER_IP=$(az network public-ip list --query "[?contains(name,'k8s-master')].ipAddress | [0]" | sed 's/"//g')
scp azureuser@${MASTER_IP}:.kube/config .
export KUBECONFIG=~/.kube/config:`pwd`/config
kubectl get nodes -o wide
```

## Cleanup

Cleanup can be performed by deleting the resource group:

```
az group delete --name=${RESOURCE_GROUP} --verbose
```
