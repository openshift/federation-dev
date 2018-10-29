# Introduction

This demo builds upon the basic [Federation V2 on Minishift](../README.md) demo,
adding a Federated Ingress object to the sample application which will
create OpenShift Routes to expose the sample application to traffic.

# Prerequisites

This demo begins after following all the steps in the parent Federation on
Minishift demo, naturally excepting the cleanup stage at the end.
In this demo, we will create a self-signed test SSL certificate. For
the production case, this should be replaced by either a commercially
signed SSL certificate, or one from a CA accepted by all intended clients.

# Why Do We Need an Ingress?

Recall from the Federation on Minishift demo that to verify the sample
application is running, it is necessary to query both the minishift IP
(typically something like 192.168.99.100) and the NodePort of the test-service
object (usually a number in the 32,000 - 33,000 range) from which we construct
a curl command, e.g.

    curl 192.168.99.100:32237

This works in a minishift cluster because the service object exposes the
application pod's :80 port on port 32237 on the master node (192.168.99.100)

In a production OpenShift cluster, Routes are used to bridge services to
outside clients. Routes are an Openshift specific object; in upstream
Kubernetes, this function is fulfilled by a relatively recent API object
known as an Ingress. In order to support Ingress, OpenShift provides by 
default a controller which converts Ingress objects into Route objects.

## Create a Federated Ingress
A Federated Route API does not exist (as of this writing), but Federated Ingress
does. Apply the following to the federated cluster example using `oc apply -f`

```
apiVersion: v1
kind: List
items:
- apiVersion: core.federation.k8s.io/v1alpha1
  kind: FederatedIngress
  metadata:
    name: test-ingress
    namespace: test-namespace
  spec:
    template:
      spec:
        rules:
        - host: test.example.com
          http:
            paths:
            - path: /
              backend:
                serviceName: test-service
                servicePort: 80
- apiVersion: core.federation.k8s.io/v1alpha1
  kind: FederatedIngressPlacement
  metadata:
    name: test-ingress
    namespace: test-namespace
  spec:
    clusterNames:
    - cluster1
    - cluster2
```

After creating the Federated Ingress, OpenShift's Route controller, which is
in charge of watching for ingress objects, will create a new route object on
each member cluster:

```
$ oc -n test-namespace get routes
NAME                 HOST/PORT          PATH      SERVICES       PORT      TERMINATION   WILDCARD
test-ingress-97dkh   test.example.com   /         test-service   80                      None
```

To see the route in action, recall the host name used to create it, and adjust
the curl command as so:

    curl -H 'Host: test.example.com' http://192.168.99.100/

This should yield a "Welcome to nginx!" default page. Try again without the `-H Host: test.example.com`
and note the "Application is not available" page. Next, try the second member cluster.

```
$ oc --context=cluster2 whoami --show-server
https://192.168.99.101:8443

$ curl -H 'Host: test.example.com' http://192.168.99.101/
```

## Add SSL to Federated Ingress

Now that our federated sample application is exposed on both clusters via a
pair of ingress-managed OpenShift Routes, let's add SSL termination to the mix.

First, create a simple self-signed SSL certificate (or copy one signed in
advance by a trusted CA):

    $ openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout test.key -out test.pem -subj "/CN=test.example.com/O=test.example.com"

Next, create a secret out of the certificate in yaml format (note: use
--dry-run to avoid adding it to the cluster at this stage.) and save it to a file:

    $ oc create secret tls test-tls --cert=test.pem --key=test.key --dry-run=true --output=yaml > federatedtlssecret.yaml

Edit the resulting yaml file and turn it into a federated secret template,
adding the appropriate headers, and indenting the original Secret's data, kind,
and type fields:

```
apiVersion: v1
kind: List
items:
- apiVersion: core.federation.k8s.io/v1alpha1
  kind: FederatedSecret
  metadata:
    name: test-tls
    namespace: test-namespace
  spec:
    template:
      data:
        tls.crt: LS0t....
        tls.key: LS0t....
      kind: Secret
      type: kubernetes.io/tls
- apiVersion: core.federation.k8s.io/v1alpha1
  kind: FederatedSecretPlacement
  metadata:
    name: test-tls
    namespace: test-namespace
  spec:
    clusterNames:
    - cluster2
    - cluster1
```

Note the FederatedSecretPlacement appended to the list in this file after the
FederatedSecret template.

Apply the template to federate the TLS certificate into both clusters:

    $ oc apply -f federatedtlssecret.yml

Check the secrets exist in both clusters:

```
$ for i in 1 2; do oc --context=cluster$i -n test-namespace describe secret test-tls; done
Name:         test-tls
Namespace:    test-namespace
Labels:       <none>
Annotations:  <none>

Type:  kubernetes.io/tls

Data
====
tls.crt:  1192 bytes
tls.key:  1704 bytes
Name:         test-tls
Namespace:    test-namespace
Labels:       <none>
Annotations:  <none>

Type:  kubernetes.io/tls

Data
====
tls.crt:  1192 bytes
tls.key:  1704 bytes
```

Finally, add a tls entry to the FederatedIngress from earlier. It works to edit the original yaml file and re-apply it with `oc apply -f`.

```
apiVersion: v1
kind: List
items:
- apiVersion: core.federation.k8s.io/v1alpha1
  kind: FederatedIngress
  metadata:
    name: test-ingress
    namespace: test-namespace
  spec:
    template:
      spec:
        tls:
        - hosts:
          - test.example.com
          secretName: test-tls
        rules:
        - host: test.example.com
          http:
            paths:
            - path: /
              backend:
                serviceName: test-service
                servicePort: 80
- apiVersion: core.federation.k8s.io/v1alpha1
  kind: FederatedIngressPlacement
  metadata:
    name: test-ingress
    namespace: test-namespace
  spec:
    clusterNames:
    - cluster1
    - cluster2
```

Test by inspecting the routes:

    $ for i in 1 2; do oc --context=cluster$i -n test-namespace describe route; done
    ...
    TLS Termination:	edge
    ...
... and using curl:

    curl -k -H 'Host: test.example.com' https://192.168.99.100/


