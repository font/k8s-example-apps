# Kubernetes Federation Issues

This document attempts to capture the current issues with Kubernetes Federation that prevents any given scenario documented in the Pac-Man Node.js application from fully
functioning as intended. These issues were experienced with Kubernetes and Kubernetes Federation v1.6.4.

## kubefed init RBAC authorization error

With Kubernetes version >= 1.6, when you attempt to `kubefed init` such as the below command:

```bash
kubefed init federation \
    --host-cluster-context=gke_${GCP_PROJECT}_us-west1-b_gce-us-west1 \
    --dns-provider='google-clouddns' --dns-zone-name=federation.com.
```

You will get the following error:

```
Error from server (Forbidden): roles.rbac.authorization.k8s.io "federation-system:federation-controller-manager" is
forbidden: attempt to grant extra privileges: [{[get] [] [secrets] [] []} {[list] [] [secrets] [] []} {[watch] [] [secrets] [] []}]
user=&{myemail@somewhere.com  [system:authenticated] map[]} ownerrules=[{[create] [authorization.k8s.io] [selfsubjectaccessreviews]
[] []} {[get] [] [] [] [/api /api/* /apis /apis/* /healthz /swaggerapi /swaggerapi/* /version]}] ruleResolutionErrors=[]
```

Kubernetes version 1.6 introduced RBAC support. This is something kubefed does not support yet.

For more details, see the [Kubernetes Federation bug #42559](https://github.com/kubernetes/kubernetes/issues/42559) and the
[Kubernetes Federation issue #44384](https://github.com/kubernetes/kubernetes/issues/44384) discussion on how kubefed should handle cluster access.

## AWS dynamic DNS name IP address out of sync with DNS entries

When using AWS, you get a dynamic DNS name from AWS for your service load balancer in the form of:

```
a94f3185a584a11e7a43d0ebdc94391f-513000480.us-east-1.elb.amazonaws.com
```

But the IP addresses pointed by that DNS can change. In the event that they change, the Federated service DNS entries are not updated to reflect the changed IP
address rendering your service unreachable.

[https://github.com/kubernetes/kubernetes/issues/35637](https://github.com/kubernetes/kubernetes/issues/35637)

## Delete cluster from federation does not clean up DNS entries

When you remove a Kubernetes cluster from the federation, it should automatically clean up the DNS entries associated with that cluster. This is not
being done. The bug is tracked in the below issue:

[https://github.com/kubernetes/kubernetes/issues/36657](https://github.com/kubernetes/kubernetes/issues/36657)

## Azure Cloud DNS Provider

Currently, Kubernetes Federation as of version 1.6 does not support the Azure Cloud DNS Provider. Only AWS Route53, CoreDNS, and Google Cloud DNS are supported.

[Kubernetes Federation Azure Cloud DNS Provider feature request](https://github.com/kubernetes/kubernetes/issues/44874)

## Replica set preferences

Should federation annotation updates to replica set preferences always keep the application available? For example, if migrating replicas from one cluster to another,
the federation control plane creates the replicas in the new cluster and terminates the old ones. But this could leave a window of time for the application to not be
available. Instead, the federation control plane could spawn the replicas in the new cluster and only once they're ready, proceed to terminate the old ones. Otherwise,
the admin will have to do these steps manually by first scaling the replicas up to a new cluster, wait for them to be ready, then scaling them down away from the previous
cluster.

## Inter-cluster private networking

Application requires using federation DNS to access cross-cluster federated services and those services need to be reachable via Load Balancer or Ingress.

`MONGO_SERVICE_HOST` itself does not work when that deployment is migrated to a different cluster. Instead, we need a way to get to service in federated cluster
perhaps by using the federated service DNS e.g. `mongo.default.federation` but that assumes a `default` namespace.

Here is an example of a 2 cluster federation, one GKE cluster in us-west region and one AWS cluster in us-east region. You can see that once the Mongo deployment
in the AWS cluster has been scaled down to just the GKE cluster, the application instances still running in the AWS cluster will still be referencing the Mongo
service cluster IP address that will no longer be reachable because there is no longer a Mongo pod running there. Instead, the applications need to use the federation
DNS for the mongo service such as `mongo.default.federation` but this assumes the use of the `default` namespace. So as you can see, `MONGO_SERVICE_HOST` does not
suffice in this case and the application would need to use the federation DNS for the service and assume a namespace, or Kubernetes federation needs a way of updating
the DNS in the local cluster to point to the federated cluster DNS name when that deployment is no longer available.

Here we are running inside one of the pacman pods inside the AWS cluster. Inside this pod we have `MONGO_SERVICE_HOST` set to `100.70.64.62` which matches the
IP address of the Mongo service cluster IP in the AWS us-east region:

```bash
root@pacman-2143500217-41pb4:/usr/src/app# printenv | grep -Ei mongo
MONGO_PORT=tcp://100.70.64.62:27017
MONGO_PORT_27017_TCP=tcp://100.70.64.62:27017
MONGO_REPLICA_SET=rs0
MONGO_SERVICE_HOST=100.70.64.62
MONGO_PORT_27017_TCP_PROTO=tcp
MONGO_PORT_27017_TCP_ADDR=100.70.64.62
MONGO_PORT_27017_TCP_PORT=27017
MONGO_SERVICE_PORT=27017

→ for c in ${KUBE_FED_CLUSTERS}; do echo; echo -----${c}-----; echo; kubectl --context=${c} get all -o wide; echo; done

-----gke_<project>_us-west1-b_gce-us-west1-----

NAME                        READY     STATUS    RESTARTS   AGE       IP          NODE
po/mongo-1244981637-d2bv1   1/1       Running   0          4h        10.52.0.5   gke-gce-us-west1-default-pool-bfdf01d8-8xsz

NAME             CLUSTER-IP      EXTERNAL-IP      PORT(S)           AGE       SELECTOR
svc/kubernetes   10.55.240.1     <none>           443/TCP           5h        <none>
svc/mongo        10.55.247.102   104.196.244.89   27017:30269/TCP   4h        name=mongo
svc/pacman       10.55.250.219   35.197.5.116     80:31996/TCP      1h        name=pacman

NAME            DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE       CONTAINER(S)   IMAGE(S)                                    SELECTOR
deploy/mongo    1         1         1            1           4h        mongo          mongo                                       name=mongo
deploy/pacman   0         0         0            0           1h        pacman         gcr.io/<project>/pacman-nodejs-app:latest   name=pacman

NAME                   DESIRED   CURRENT   READY     AGE       CONTAINER(S)   IMAGE(S)                                    SELECTOR
rs/mongo-1244981637    1         1         1         4h        mongo          mongo                                       name=mongo,pod-template-hash=1244981637
rs/pacman-2143500217   0         0         0         1h        pacman         gcr.io/<project>/pacman-nodejs-app:latest   name=pacman,pod-template-hash=2143500217


-----us-east-1.subdomain.example.com-----

NAME                         READY     STATUS    RESTARTS   AGE       IP           NODE
po/pacman-2143500217-41pb4   1/1       Running   0          11m       100.96.1.6   ip-172-20-50-75.ec2.internal
po/pacman-2143500217-z9l08   1/1       Running   0          11m       100.96.2.6   ip-172-20-38-118.ec2.internal

NAME             CLUSTER-IP      EXTERNAL-IP                                                               PORT(S)           AGE       SELECTOR
svc/kubernetes   100.64.0.1      <none>                                                                    443/TCP           5h        <none>
svc/mongo        100.70.64.62    a94f3185a584a11e7a43d0ebdc94391f-513000480.us-east-1.elb.amazonaws.com    27017:32639/TCP   4h        name=mongo
svc/pacman       100.65.121.33   a92720628586411e7a43d0ebdc94391f-1121613428.us-east-1.elb.amazonaws.com   80:30407/TCP      1h        name=pacman

NAME            DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE       CONTAINER(S)   IMAGE(S)                                    SELECTOR
deploy/mongo    0         0         0            0           4h        mongo          mongo                                       name=mongo
deploy/pacman   2         2         2            2           1h        pacman         gcr.io/<project>/pacman-nodejs-app:latest   name=pacman

NAME                   DESIRED   CURRENT   READY     AGE       CONTAINER(S)   IMAGE(S)                                    SELECTOR
rs/mongo-1244981637    0         0         0         4h        mongo          mongo                                       name=mongo,pod-template-hash=1244981637
rs/pacman-2143500217   2         2         2         1h        pacman         gcr.io/<project>/pacman-nodejs-app:latest   name=pacman,pod-template-hash=2143500217
```

Now when we resolve the `mongo` service inside the pacman pod in the AWS cluster, we can see that it resolves to the same mongo service cluster IP. This is
a problem because the IP address will not reach any mongo deployment as no mongo deployment is running in the AWS cluster.

```bash
root@pacman-2143500217-41pb4:/usr/src/app# dig mongo +search

; <<>> DiG 9.9.5-9+deb8u11-Debian <<>> mongo +search
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 53831
;; flags: qr aa rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 0

;; QUESTION SECTION:
;mongo.default.svc.cluster.local. IN    A

;; ANSWER SECTION:
mongo.default.svc.cluster.local. 30 IN  A       100.70.64.62

;; Query time: 1 msec
;; SERVER: 100.64.0.10#53(100.64.0.10)
;; WHEN: Sat Jun 24 00:32:27 UTC 2017
;; MSG SIZE  rcvd: 65
```

Instead, if we now check the federation DNS for the mongo service i.e. `mongo.default.federation` we would properly reach a mongo instance because the
DNS is always updated to point to an available deployment for that service.

```bash
root@pacman-2143500217-41pb4:/usr/src/app# dig mongo.default.federation +search

; <<>> DiG 9.9.5-9+deb8u11-Debian <<>> mongo.default.federation +search
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 42489
;; flags: qr aa rd ra; QUERY: 1, ANSWER: 4, AUTHORITY: 0, ADDITIONAL: 0

;; QUESTION SECTION:
;mongo.default.federation.svc.cluster.local. IN A

;; ANSWER SECTION:
mongo.default.federation.svc.cluster.local. 0 IN CNAME mongo.default.federation.svc.us-east-1a.us-east-1.example.com.
mongo.default.federation.svc.us-east-1a.us-east-1.example.com. 0 IN CNAME mongo.default.federation.svc.us-east-1.example.com.
mongo.default.federation.svc.us-east-1.example.com. 0 IN CNAME mongo.default.federation.svc.example.com.
mongo.default.federation.svc.example.com. 0 IN A 104.196.244.89

;; Query time: 155 msec
;; SERVER: 100.64.0.10#53(100.64.0.10)
;; WHEN: Sat Jun 24 00:32:29 UTC 2017
;; MSG SIZE  rcvd: 239
```

## Federation Required From Beginning

In order to use the features of Kubernetes Federation, one has to start with Kubernetes Federation. That is, as of this writing, you cannot seem to
start with a cluster or multiple clusters and then later decide that you want to federate them. For example, when you deploy the federation control
plane, it does not query the state of the cluster(s) to determine what resources are already deployed to manage through the federation. Instead, you
have to have started and deployed all of your applications through the federation control plane in order to federate them later. This seems like a
feature of federation that is missing in order to allow existing customers not using federation to later adopt it.

## AWS Dynamic DNS was not updated in DNS

After waiting for a long time, the AWS dynamic DNS IP addresses were not updated in the federation DNS provider. Here is an example:

```bash
→ for i in ${KUBE_FED_CLUSTERS}; do echo; echo -----${i}-----; echo; kubectl --context=${i} get all -o wide; echo; done

-----gke_${GCP_PROJECT}_us-west1-b_gce-us-west1-----

NAME                        READY     STATUS    RESTARTS   AGE       IP          NODE
po/mongo-1244981637-d2bv1   1/1       Running   0          28m       10.52.0.5   gke-gce-us-west1-default-pool-bfdf01d8-8xsz

NAME             CLUSTER-IP      EXTERNAL-IP      PORT(S)           AGE       SELECTOR
svc/kubernetes   10.55.240.1     <none>           443/TCP           1h        <none>
svc/mongo        10.55.247.102   104.196.244.89   27017:30269/TCP   29m       name=mongo

NAME           DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE       CONTAINER(S)   IMAGE(S)   SELECTOR
deploy/mongo   1         1         1            1           28m       mongo          mongo      name=mongo

NAME                  DESIRED   CURRENT   READY     AGE       CONTAINER(S)   IMAGE(S)   SELECTOR
rs/mongo-1244981637   1         1         1         28m       mongo          mongo      name=mongo,pod-template-hash=1244981637


-----us-east-1.subdomain.example.com-----

NAME                        READY     STATUS    RESTARTS   AGE       IP           NODE
po/mongo-1244981637-7vlqk   1/1       Running   0          28m       100.96.1.3   ip-172-20-50-75.ec2.internal

NAME             CLUSTER-IP     EXTERNAL-IP                                                              PORT(S)           AGE       SELECTOR
svc/kubernetes   100.64.0.1     <none>                                                                   443/TCP           50m       <none>
svc/mongo        100.70.64.62   a94f3185a584a11e7a43d0ebdc94391f-513000480.us-east-1.elb.amazonaws.com   27017:32639/TCP   29m       name=mongo

NAME           DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE       CONTAINER(S)   IMAGE(S)   SELECTOR
deploy/mongo   1         1         1            1           28m       mongo          mongo      name=mongo

NAME                  DESIRED   CURRENT   READY     AGE       CONTAINER(S)   IMAGE(S)   SELECTOR
rs/mongo-1244981637   1         1         1         28m       mongo          mongo      name=mongo,pod-template-hash=1244981637
```

```bash
→ dig a94f3185a584a11e7a43d0ebdc94391f-513000480.us-east-1.elb.amazonaws.com

; <<>> DiG 9.10.4-P8-RedHat-9.10.4-4.P8.fc24 <<>> a94f3185a584a11e7a43d0ebdc94391f-513000480.us-east-1.elb.amazonaws.com
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 60447
;; flags: qr rd ra; QUERY: 1, ANSWER: 2, AUTHORITY: 4, ADDITIONAL: 1

;; OPT PSEUDOSECTION:
; EDNS: version: 0, flags:; udp: 4096
;; QUESTION SECTION:
;a94f3185a584a11e7a43d0ebdc94391f-513000480.us-east-1.elb.amazonaws.com.        IN A

;; ANSWER SECTION:
a94f3185a584a11e7a43d0ebdc94391f-513000480.us-east-1.elb.amazonaws.com. 60 IN A 34.194.248.107
a94f3185a584a11e7a43d0ebdc94391f-513000480.us-east-1.elb.amazonaws.com. 60 IN A 52.202.24.215

;; AUTHORITY SECTION:
us-east-1.elb.amazonaws.com. 111 IN     NS      ns-235.awsdns-29.com.
us-east-1.elb.amazonaws.com. 111 IN     NS      ns-934.awsdns-52.net.
us-east-1.elb.amazonaws.com. 111 IN     NS      ns-1793.awsdns-32.co.uk.
us-east-1.elb.amazonaws.com. 111 IN     NS      ns-1119.awsdns-11.org.

;; Query time: 28 msec
;; SERVER: 127.0.0.1#53(127.0.0.1)
;; WHEN: Fri Jun 23 13:03:58 PDT 2017
;; MSG SIZE  rcvd: 268
```

Yet, the DNS was not updating after 20+ minutes. It did take a bit for the AWS dynamic DNS to resolve to the corresponding IP addresses of its load balancers.
But even after it successfully updated it, it took 20+ minutes.

```bash
→ gcloud dns record-sets list --zone federation --filter mongo
NAME                                                              TYPE   TTL  DATA
mongo.default.federation.svc.example.com.                       A      180  104.196.244.89
mongo.default.federation.svc.us-east-1.example.com.             CNAME  180  mongo.default.federation.svc.example.com.
mongo.default.federation.svc.us-east-1a.us-east-1.example.com.  CNAME  180  mongo.default.federation.svc.us-east-1.example.com.
mongo.default.federation.svc.us-west1.example.com.              A      180  104.196.244.89
mongo.default.federation.svc.us-west1-b.us-west1.example.com.   A      180  104.196.244.89
```

Nothing in the federation controller manager logs proved useful so after restarting the federation controller manager with `--v=4` it successfully updated
the DNS entries for AWS. [Here are the logs before and after the restart](aws-dns-bug.md).

## Get deployment in federation context UP-TO-DATE field not updated

When creating a Kubernetes deployment through the federation context, the `UP-TO-DATE` column is not updated. This is evident when you loop through each of the
contexts containing your Kubernetes clusters being federated to find that those deployments do in fact show the `UP-TO-DATE` column is updated.

Here is an example:

```bash
→ kubectl get deploy mongo -o wide
NAME      DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE       CONTAINER(S)   IMAGE(S)   SELECTOR
mongo     3         3         0            3           12m       mongo          mongo      name=mongo
→ for i in ${GCE_ZONES}; do
    kubectl --context=gke_${GCP_PROJECT}_us-${i}1-b_gce-us-${i}1 get deployment
  done
NAME      DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
mongo     1         1         1            1           12m
NAME      DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
mongo     1         1         1            1           12m
NAME      DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
mongo     1         1         1            1           12m
```
