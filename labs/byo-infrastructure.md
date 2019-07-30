<a id="markdown-bring-your-own-infrastructure" name="bring-your-own-infrastructure"></a>

# BYO Infrastructure

This lab is prepared for the Red Hat Tech Exchange 2019 event.

For this lab users are presented with pre-existing infrastructure as well as some automation mechanisms.

This document aims to define all the required steps needed to be able to follow this lab outside of the RHTE event.

## Clusters Deployment

This Lab requires at least three [OpenShift Container Platform](https://www.openshift.com/) 4.1 clusters.

The clusters can be deployed using the [developer preview on AWS](https://cloud.redhat.com/openshift/install)

## Tooling Download

The following tools are used during the labs and must be present in the system used by the student to interact with the clusters.

* kubefedctl
    
    ```sh
    curl -LOs https://github.com/kubernetes-sigs/kubefed/releases/download/v0.1.0-rc4/kubefedctl-0.1.0-rc4-linux-amd64.tgz
    tar xzf kubefedctl-0.1.0-rc4-linux-amd64.tgz -C /usr/local/bin/
    chmod +x /usr/local/bin/kubefedctl
    rm -f kubefedctl.tgz
    ```
* cfssl

    ```sh
    curl -LOs https://pkg.cfssl.org/R1.2/cfssl_linux-amd64
    mv cfssl_linux-amd64 /usr/local/bin/cfssl
    chmod +x /usr/local/bin/cfssl
    ```
* cfssljson

    ```sh
    curl -LOs https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64
    mv cfssljson_linux-amd64 /usr/local/bin/cfssljson
    chmod +x /usr/local/bin/cfssljson
    ```

## Deploy KubeFed Operator

KubeFed Operator will be deployed to the first cluster, the following steps must be run **only** in one of the clusters as cluster admin.

1. Create the `kube-federation-system` namespace
    
    ```sh
    oc create ns kube-federation-system
    ```
2. Create the `CatalogSourceConfig`

    ```sh
    cat <<-EOF | oc apply -f -
    ---
    apiVersion: operators.coreos.com/v1
    kind: CatalogSourceConfig
    metadata:
      name: installed-kubefed-kube-federation-system
      namespace: openshift-marketplace
    spec:
      csDisplayName: Community Operators
      csPublisher: Community
      targetNamespace: kube-federation-system
      packages: kubefed-operator
    ---
    EOF
    ```
3. Create the `OperatorGroup`

    ```sh
    cat <<-EOF | oc apply -n kube-federation-system -f -
    ---
    apiVersion: operators.coreos.com/v1
    kind: OperatorGroup
    metadata:
      name: kubefed
    spec:
      targetNamespaces:
      - kube-federation-system
    ---
    EOF
    ```
4. Create the `Subscription`

    ```sh
    cat <<-EOF | oc apply -n kube-federation-system -f -
    ---
    apiVersion: operators.coreos.com/v1alpha1
    kind: Subscription
    metadata:
      name: federation
    spec:
      channel: alpha
      installPlanApproval: Manual
      name: kubefed-operator
      package: kubefed-operator
      startingCSV: kubefed-operator.v0.1.0
      source: installed-kubefed-kube-federation-system
      sourceNamespace: kube-federation-system
    ---
    EOF
    ```
5. Approve the `InstallPlan` (It may take some time to be created)

    ```sh
    oc -n kube-federation-system get installplan
    oc -n kube-federation-system patch installplan <installplan_name> --type merge -p '{"spec":{"approved":true}}'
    ```
6. Wait `ClusterServiceVersion` to succeed (it may take some time to Succeed)

    ```sh
    oc -n kube-federation-system get csv
    ```

## Deploy the HAProxy LoadBalancer

This procedure assumes you already have three clusters deployed and configured
as three contexts (cluster1, cluster2 and cluster3) in the `oc` tool.


1. Change directory to `haproxy-yaml`

    ```sh
    cd federation-dev/labs/haproxy-yaml
    ```
2. Create the namespace where the HAProxy LB will be deployed
    ```sh
    oc --context cluster1 create ns haproxy-lb
    ```
3. Create the HAProxy Route for external access

    ```sh
    cat <<-EOF | oc --context cluster1 apply -n haproxy-lb -f -
    ---
    apiVersion: route.openshift.io/v1
    kind: Route
    metadata:
      labels:
        app: haproxy-lb
      name: haproxy-lb
    spec: 
      port:
        targetPort: 8080
      subdomain: ""
      tls:
        insecureEdgeTerminationPolicy: Redirect
        termination: edge
      to:
        kind: Service
        name: haproxy-lb
        weight: 100
      wildcardPolicy: None
    ---
    EOF
    ```
4. Create the configmap with the HAProxy configuration file

    ```sh
    # Export the required vars
    HAPROXY_LB_ROUTE=$(oc --context cluster1 -n haproxy-lb get route pacman-lb -o jsonpath='{.status.ingress[*].host}')
    PACMAN_CLUSTER1=pacman.$(oc --context=cluster1 -n openshift-console get route console -o jsonpath='{.status.ingress[*].host}' | sed "s/.*\(apps.*\)/\1/g")
    PACMAN_CLUSTER2=pacman.$(oc --context=cluster2 -n openshift-console get route console -o jsonpath='{.status.ingress[*].host}' | sed "s/.*\(apps.*\)/\1/g")
    PACMAN_CLUSTER3=pacman.$(oc --context=cluster3 -n openshift-console get route console -o jsonpath='{.status.ingress[*].host}' | sed "s/.*\(apps.*\)/\1/g")
    # Copy the sample configmap
    cp haproxy.tmpl haproxy
    # Update the HAProxy configuration
    sed -i "s/<pacman_lb_hostname>/${HAPROXY_LB_ROUTE}/g" haproxy
    sed -i "s/<server1_name> <server1_pacman_route>:<route_port>/cluster1 ${PACMAN_CLUSTER1}:80/g" haproxy
    sed -i "s/<server2_name> <server2_pacman_route>:<route_port>/cluster2 ${PACMAN_CLUSTER2}:80/g" haproxy
    sed -i "s/<server3_name> <server3_pacman_route>:<route_port>/cluster3 ${PACMAN_CLUSTER3}:80/g" haproxy
    # Create the configmap
    oc --context cluster1 -n haproxy-lb create configmap haproxy --from-file=haproxy
    ```
5. Create the HAProxy ClusterIP Service

    ```sh
    oc --context cluster1 -n haproxy-lb create -f haproxy-clusterip-service.yaml
    ```

6. Create the HAProxy Deployment

    ```sh
    oc --context cluster1 -n haproxy-lb create -f haproxy-deployment.yaml
    ```
7. That's it. The value of `${HAPROXY_LB_ROUTE}` is the hostname that you will
use to connect to the Pacman application being load balanced by HAProxy

## Create the MongoDB Certificates

This procedure assumes you already have three clusters deployed and configured
as three contexts (cluster1, cluster2 and cluster3) in the `oc` tool.

1. Change directory to `mongo-yaml`

    ```sh
    cd federation-dev/labs/mongo-yaml
    ```
2. Edit the file `ca-config.json`:

    ```sh
    vim ca-config.json
    ```
    2.1 Place the content below inside the `ca-config.json` file

    ```json
    {
      "signing": {
        "default": {
          "expiry": "8760h"
        },
        "profiles": {
          "kubernetes": {
            "usages": ["signing", "key encipherment", "server auth", "client auth"],
            "expiry": "8760h"
          }
        }
      }
    }
    ```
3. Edit the file `ca-csr.json`

    ```sh
    vim ca-csr.json
    ```
    3.1 Place the content below inside the `ca-csr.json` file

    ```json
    {
      "CN": "Kubernetes",
      "key": {
        "algo": "rsa",
        "size": 2048
      },
      "names": [
        {
          "C": "US",
          "L": "Austin",
          "O": "Kubernetes",
          "OU": "TX",
          "ST": "Texas"
        }
      ]
    }
    ```
4. Edit the file `mongodb-csr.json`

    ```sh
    vim mongodb-csr.json
    ```
    3.1 Place the content below inside the `mongodb-csr.json` file

    ```json
    {
      "CN": "kubernetes",
      "key": {
        "algo": "rsa",
        "size": 2048
      },
      "names": [
        {
          "C": "US",
          "L": "Austin",
          "O": "Kubernetes",
          "OU": "TX",
          "ST": "Texas"
        }
      ]
    }
    ```

We will use OpenShift Routes to provide connectivity between MongoDB Replicas. As we said before, MongoDB will be configured to use TLS communications, we need to generate certificates with proper hostnames configured within them.

Follow the instructions below to generate a PEM file which include:
* MongoDB's Certificate Private Key
* MongoDB's Certificate Public Key

1. Export some variables with information that will be used for generate the certificates

    ```sh
    NAMESPACE=mongo
    SERVICE_NAME=mongo
    ROUTE_CLUSTER1=mongo-cluster1.$(oc --context=cluster1 -n openshift-console get route console -o jsonpath='{.status.ingress[*].host}' | sed "s/.*\(apps.*\)/\1/g")
    ROUTE_CLUSTER2=mongo-cluster2.$(oc --context=cluster2 -n openshift-console get route console -o jsonpath='{.status.ingress[*].host}' | sed "s/.*\(apps.*\)/\1/g")
    ROUTE_CLUSTER3=mongo-cluster3.$(oc --context=cluster3 -n openshift-console get route console -o jsonpath='{.status.ingress[*].host}' | sed "s/.*\(apps.*\)/\1/g")
    SANS="localhost,localhost.localdomain,127.0.0.1,${ROUTE_CLUSTER1},${ROUTE_CLUSTER2},${ROUTE_CLUSTER3},${SERVICE_NAME},${SERVICE_NAME}.${NAMESPACE},${SERVICE_NAME}.${NAMESPACE}.svc.cluster.local"
    ```
2. Generate the CA

    ```sh
    cfssl gencert -initca ca-csr.json | cfssljson -bare ca
    ```
3. Generate the MongoDB Certificates

    ```sh
    cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -hostname=${SANS} -profile=kubernetes mongodb-csr.json | cfssljson -bare mongodb
    ```
4. Combine Key and Certificate

    ```sh
    cat mongodb-key.pem mongodb.pem > mongo.pem
    ```
