# Federation Dev
This repository is a place holder for various demonstrations, labs, and examples
of the use of Federation V2. There are two ways two use Federation V2 currently.

## What is Federation
Put quite simply, Federation is the process of connecting one or more Kubernetes clusters. The explanation from OperatorHub states
``
Kubernetes Federation is a tool to sync (aka "federate") a set of Kubernetes objects from a "source" into a set of other clusters. Common use-cases include federating Namespaces across all of your clusters or rolling out an application across several geographically distributed clusters. The Kubernetes Federation Operator runs all of the components under the hood to quickly get up and running with this powerful concept. Federation is a key part of any Hybrid Cloud capability.
``

### Namespace Scoped labs
Namespace scoped Federation will initially be the only supported mechanism for federating
multiple OpenShift/Kubernetes environments. Namespace scoped Federation uses OperatorHub
which is included within OpenShift to install the Federation Operator.
Using [OpenShift Container Plaform 4](./README-ocp4.md)

### Cluster Scoped labs
Cluster scoped Federation using an Operator is still in progress. The examples below
will run through the procedures of manually configuring cluster scoped Federation.
Using [minishift](./README-minishift.md)<br/>
Using [cdk](./README-minishift.md)
