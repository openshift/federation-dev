# Deploying a Federated Pacman Application backed by a Federated MongoDB ReplicaSet

This document explains how the automated demo works under the hood.

## Software Versions
  - MongoDB Version: v4.1.5, Git Version: f3349bac21f200cf2f9854eb51b359d3cbee3617
  - OpenShift Version: v4.1, Kubernetes: v1.13.4+8cd4e29
  - Kubefed Version: v0.0.10

## Diagrams

### MongoDB ReplicaSet Architecture

![Federated Mongo Diagram](../images/federated-mongo-diagram.png)

* There is a MongoDB pod running on each OpenShift 4 Cluster, each pod has its own storage (provisioned by a block type StorageClass)
* The MongoDB pods are configured as a MongoDB ReplicaSet and communications happening between them use TLS
* The OpenShift Routes are configured as `passthrough` termination, we need the connection to remain plain TLS (no HTTP headers involved)
* The MongoDB pods interact between each other using the OpenShift Routes (OCP Nodes where MongoDB pods are running must be able to connect to the other clusters OpenShift Routers)

### How is the MongoDB ReplicaSet configured

Each OpenShift cluster has a MongoDB pod running. There is an OpenShift `service` which routes the traffic received on port `27017/TCP` to the MongoDB pod's port `27017/TCP`.

There is an OpenShift `route` created on each cluster, the `route` termination is `passthrough`  (the HAProxy won't add HTTP headers to the connections). Earch `route` listens for connections on port `443/TCP` and reverse proxies traffic received to the mongo `service` on port `27017/TCP`.

The MongoDB pods have been configured to use TLS, so all connections will be made using TLS (a TLS certificate with `route` hostnames as well as `services` hostnames configured as SANs is used by MongoDB pods).

Once the three pods are up and running, the MongoDB ReplicaSet is configured using the OpenShift `routes` hostnames as MongoDB endpoints.

We will have something like this:

* ReplicaSet Primary Member: mongo-east1.apps.cluster1.example.com:443
* ReplicaSet Secondary Members: mongo-east2.apps.cluster2.example.com:443, mongo-west2.apps.cluster3.example.com:443

In the event that one of the MongoDB pods fails / stops, the MongoDB ReplicaSet will reconfigure itself, and once a new pod replaces the failed/stopped one, the MongoDB ReplicaSet will reconfigure that pod and include it as a member again. In the meantime the MongoDB Quorum Algorithm will determine if the MongoDB ReplicaSet is RO or RW.

### Demo Application Architecture

![Demo Application Diagram](../images/pacman-app-diagram.png)

* There is a Pacman pod running on each OpenShift 4 Cluster, each pod can connect to any MongoDB pod
* The MongoDB connection protocol will determine which MongoDB pod Pacman should connect to based on which pod is acting as MongoDB ReplicaSet primary member
* There is an external DNS name `pacman.sysdeseng.com` that points to a custom load balancer, HAProxy in this case
* The HAProxy lb is configured to distribute incoming traffic across the three different Pacman pods in a Round Robin fashion

## Demo Steps

### Kubefed Initialization + TLS Certificates Generation
1. Based on the info provided via the `inventory.json` file or via the standard input, three different contexts will be created on the `oc` tool configuration.
2. Once the contexts are created, the script will create a new namespace and deploy the Kubefed operator using the Operator Marketplace
3. The MongoDB replicas will communicate with each other using TLS, so the demo script will create the required CA and Certificates for this to happen
4. Once we have the required certificates, the demo script will generate some yaml files which need to include those certificates
5. At this point, we will have the namespace distributed across the three different clusters and the demo script will start deploying the federated MongoDB ReplicaSet
  
### Federated MongoDB ReplicaSet deployment

1. First, two FederatedSecrets are created. One containing the TLS certificates and other containing the admin credentials for MongoDB.
2. After that, the FederatedService for MongoDB is created
3. The MongoDB instances need storage for storing its data, a FederatedPersistentVolume is created for that
4. A FederatedDeployment is created next, this FederatedDeployment ensures a MongoDB deployment configured with 1 replica exists in each cluster
5. OpenShift Routes are created in order to get external traffic to our pods
6. The MongoDB ReplicaSet configuration is automated and only requires to label a MongoDB pod specifying that it is the primary member

### Federated Pacman deployment

1. A FederatedSecret which contains user credentials for MongoDB is created 
3. A FederatedService is created
4. In order to get traffic to our Pacman application, a FederatedIngress is created
5. After that, the demo script creates a FederatedDeployment which ensures a Pacman App pod runs on each cluster

### Demo Flow

1. User will play Pacman and store some highscores on different cloud zones
2. The primary MongoDB pod will be deleted to simulate a "DR" scenario
3. User will continue playing and storing highscores
4. Pacman application will be scaled down to run on one cluster only
5. The MongoDB pod will be recovered automatically
6. Pacman application will be scaled up again