# Federation Dev
This repository contains demonstrations, labs, and examples
of the use of Kubefed and/or the management of multiple OpenShift clusters.

## What is Federation
Put quite simply, Federation is the process of connecting one or more Kubernetes clusters. The explanation from OperatorHub states
``
Kubernetes Federation is a tool to sync (aka "federate") a set of Kubernetes objects from a "source" into a set of other clusters. Common use-cases include federating Namespaces across all of your clusters or rolling out an application across several geographically distributed clusters. The Kubernetes Federation Operator runs all of the components under the hood to quickly get up and running with this powerful concept. Federation is a key part of any Hybrid Cloud capability.
``
There are two ways to use Kubefed currently: Namespace and Cluster scoped.
For a breakdown of what this entails, see our [KubeFed Cluster-Scoped Vs Namespace-Scoped](docs/kubefed-scope.md) guide.

### RHTE lab
If you are attend Red Hat tech exchange follow the link below will bring you to the first lab.<br>
[Red Hat Tech Exchange Lab - Hands on with Red Hat Multi-Cluster Federation: Application Portability](./labs/README.md)<br>

### Namespace Scoped labs
Namespace scoped Federation was initially the only supported mechanism for federating
multiple OpenShift/Kubernetes environments. Namespace scoped Federation uses OperatorHub,
which is included within OpenShift 4.1, to install the Federation Operator.

* A simple application federated [OpenShift Container Plaform 4](./docs/ocp4-namespace-scoped.md)
* Federated MongoDB and *Pacman* [Federating an application with a Database](./federated-mongodb/README.md)
* An automated demo exists to demonstrate running Kubefed in 3.11 and 4.x clusters [Automated Demo](./automated-demo/README.md)

OpenShift 3.11 versions for the simple application scenario are also available:

* Using [Minishift](./docs/minishift.md)
* Using [CDK](./docs/cdk.md)

### Cluster Scoped
Cluster scoped KubeFed is now supported as of version 0.1.0 of the KubeFed
operator.

* A simple application federated [OpenShift Container Platform 4 (cluster scoped)](./docs/ocp4-cluster-scoped.md)
