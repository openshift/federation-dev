# Federation Dev
This repository is a place holder for various demonstrations, labs, and examples
of the use of KubeFed.

## What is Federation
Put quite simply, Federation is the process of connecting one or more
Kubernetes clusters. KubeFed is the Kubernetes project supporting the concept
of Federation on Kubernetes clusters. The explanation from OperatorHub states

``
Kubernetes Federation is a tool to sync (aka "federate") a set of Kubernetes objects from a "source" into a set of other clusters. Common use-cases include federating Namespaces across all of your clusters or rolling out an application across several geographically distributed clusters. The Kubernetes Federation Operator runs all of the components under the hood to quickly get up and running with this powerful concept. Federation is a key part of any Hybrid Cloud capability.
``

There are two ways to use Kubefed currently: Namespace and Cluster scoped.

### Namespace Scoped labs
Namespace scoped KubeFed was initially the only supported mechanism for federating
multiple OpenShift/Kubernetes environments. Namespace scoped KubeFed uses OperatorHub,
which is included within OpenShift 4.1, to install the KubeFed Operator.


[Lab 1 - Introduction and Prerequisites](./labs/1.md)<br>
[Lab 2 - Create OpenShift Clusters and Configure Context](./labs/2.md)<br>
[Lab 3 - Deploy Federation](./labs/3.md)<br>
[Lab 4 - Example Application One](./labs/4.md)<br>
[Lab 5 - Federating MongoDB Introduction and namespace Creation](./labs/5.md)<br>
[Lab 6 - Kubeconfig, Tools and Join Clusters](./labs/6.md)<br>
[Lab 7 - Creating Certificates](./labs/7.md)<br>
[Lab 8 - Deploying MongoDB](./labs/8.md)<br>

### Cluster Scoped
Cluster scoped KubeFed is now supported as of version 0.1.0 of the KubeFed
operator. A walkthrough using cluster scoped KubeFed is currently under
development.

