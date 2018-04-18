# Sample Federation-v2 Demo

## Prereqs

- minikube
- kubectl
- crinit
- apiserver-builder

## Create clusters

```bash
minikube start -p us-west
minikube start -p us-east
kubectl config use-context us-west
kubectl config set-context us-west --namespace=test-namespace
kubectl config set-context us-east --namespace=test-namespace
```

## Create Federation Namespace

```bash
kubectl create ns federation
```

## Deploy Cluster Registry

```bash
crinit aggregated init mycr --host-cluster-context=us-west
kubectl config delete-context mycr
kubectl config delete-cluster mycr
```

## Deploy Federation

```bash
apiserver-boot run in-cluster --name federation --namespace federation --image <registry/username/imagename:tag>
```

## Verify Clusters in Config

```bash
kubectl config get-clusters
```

## Join Clusters to Federation

```bash
go build -o bin/kubefnord cmd/kubefnord/kubefnord.go
./bin/kubefnord join us-west --host-cluster-context us-west --add-to-registry --v=2
./bin/kubefnord join us-east --host-cluster-context us-west --add-to-registry --v=2
```

## Check Status of Joined Clusters

```bash
kubectl -n federation describe federatedclusters
```

## Create all the resources

```bash
git clone https://github.com/font/k8s-example-apps.git
cd k8s-example-apps/sample-fed-v2-demo/configs
kubectl create -f .
```

## Check Status

```bash
for i in us-west us-east; do echo; echo ------------ ${i} ------------; echo; kubectl --context ${i} get ns test-namespace; echo; echo; done
for i in us-west us-east; do echo; echo ------------ ${i} ------------; echo; kubectl --context ${i} get configmaps; echo; echo; done
for i in us-west us-east; do echo; echo ------------ ${i} ------------; echo; kubectl --context ${i} get secrets; echo; echo; done
for i in us-west us-east; do echo; echo ------------ ${i} ------------; echo; kubectl --context ${i} get rs; echo; echo; done
```

## Update FederatedNamespacePlacement

Remove `us-east` and `status`:

```bash
kubectl -n test-namespace edit federatednamespaceplacement test-namespace
```

Then verify `replicasets`:

```bash
for i in us-west us-east; do echo; echo ------------ ${i} ------------; echo; kubectl --context ${i} -n test-namespace get rs; echo; echo; done
```

Update `FederatedNamespacePlacement` to add back `us-east` and remove `status`
again:

```bash
kubectl -n test-namespace edit federatednamespaceplacement test-namespace
```

Then verify replicasets:

```bash
for i in us-west us-east; do echo; echo ------------ ${i} ------------; echo; kubectl --context ${i} -n test-namespace get rs; echo; echo; done
```

## Conclusion

So you can see that Federation-v2 handles workloads by joining clusters
into the workload, allowing you to specify the resource types that you want to
propagate, override certain parameters that you want to differentiate in your
clusters, and specify the placement rules for where you want that resource type
to be propagated.

## Cleanup

### Delete clusters

```bash
minikube delete -p us-east
minikube delete -p us-west
```
