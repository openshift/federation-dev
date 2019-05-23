# Federation Dev
This repository is a place holder for various demonstrations, labs, and examples
of the use of Kubefed.

## What is Federation
Put quite simply, Federation is the process of connecting one or more Kubernetes clusters. The explanation from OperatorHub states
``
Kubernetes Federation is a tool to sync (aka "federate") a set of Kubernetes objects from a "source" into a set of other clusters. Common use-cases include federating Namespaces across all of your clusters or rolling out an application across several geographically distributed clusters. The Kubernetes Federation Operator runs all of the components under the hood to quickly get up and running with this powerful concept. Federation is a key part of any Hybrid Cloud capability.
``
There are two ways to use Kubefed currently: Namespace and Cluster scoped.

### Namespace Scoped labs
Namespace scoped Federation will initially be the only supported mechanism for federating
multiple OpenShift/Kubernetes environments. Namespace scoped Federation uses OperatorHub,
which is included within OpenShift 4.1, to install the Federation Operator.

* A simple application federated [OpenShift Container Plaform 4](./README-ocp4.md)
* Federated MongoDB and *Pacman* [Federating an application with a Database](./federated-mongodb/README.md)

OpenShift 3.11 versions for the simple application scenario are also available:

* Using [Minishift](./README-minishift.md)
* Using [CDK](./README-minishift.md)

### Cluster Scoped
At the moment cluster-scoped federation is not supported by the operator. Once the cluster scoped is enabled via the operator we will update the instructions to cover that user case as well.
