**Table of Contents**

<!-- TOC depthFrom:1 insertAnchor:true orderedList:true -->

- [Introduction](#introduction)
- [Prerequisites](#prerequisites)
  - [Install the kubefedctl binary](#install-the-kubefedctl-binary)
  - [Download the example code](#download-the-example-code)
- [Federation deployment](#federation-deployment)
  - [Create the two OpenShift clusters](#create-the-two-openshift-clusters)
  - [Configure client context for cluster admin access](#configure-client-context-for-cluster-admin-access)
  - [Deploy Federation](#deploy-federation)
  - [Register the clusters](#register-the-clusters)
- [Example application](#example-application)
  - [Deploy the application](#deploy-the-application)
  - [Verify that the application is running](#verify-that-the-application-is-running)
  - [Modify placement](#modify-placement)
- [Clean up](#clean-up)
- [What’s next?](#whats-next)

<!-- /TOC -->

<a id="markdown-introduction" name="introduction"></a>
# Introduction

This demo is a simple deployment of [KubeFed
Operator](https://operatorhub.io/operator/kubefed-operator) on two OpenShift
clusters. A sample application is deployed to both clusters through the
KubeFed controller.

<a id="markdown-pre-requisites" name="pre-requisites"></a>
# Prerequisites

The Federation Operator requires at least one [OpenShift Container Platform](https://www.openshift.com/) 4.1 cluster.

This walkthrough will use two OCP 4.1 clusters deployed using the [Installer-Provisioned Infrastructure](https://cloud.redhat.com/openshift/install/aws) installation type.

<a id="markdown-install-the-kubefedctl-binary" name="install-the-kubefedctl-binary"></a>
## Install the kubefedctl binary

The `kubefedctl` tool manages federated cluster registration. Download the
v0.1.0-rc3 release and unpack it into a directory in your PATH (the
example uses `$HOME/bin`):

~~~sh
curl -Ls https://github.com/kubernetes-sigs/kubefed/releases/download/v0.1.0-rc3/kubefedctl-0.1.0-rc3-linux-amd64.tgz | tar xz -C ~/bin
~~~

Verify that `kubefedctl` is working:

~~~sh
kubefedctl version

kubefedctl version: version.Info{Version:"v0.1.0-rc3", GitCommit:"d188d227fe3f78f33d74d9a40b3cb701c471cc7e", GitTreeState:"clean", BuildDate:"2019-06-25T00:27:58Z", GoVersion:"go1.12.5", Compiler:"gc", Platform:"linux/amd64"}
~~~

<a id="markdown-download-the-example-code" name="download-the-example-code"></a>
## Download the example code

Clone the demo code to your local machine:

~~~sh
git clone https://github.com/openshift/federation-dev.git
cd federation-dev/
~~~

<a id="markdown-federation-deployment" name="federation-deployment"></a>
# Federation deployment

<a id="markdown-create-the-two-openshift-clusters" name="create-the-two-openshift-clusters"></a>
## Create the two OpenShift clusters

Follow the [Installer Provisioned Infrastructure Instructions](https://cloud.redhat.com/openshift/install/aws/installer-provisioned) for installing two OpenShift 4.1 clusters on AWS. Be sure to employ the `--dir` option with a distinct directory for each cluster you create.

<a id="markdown-configure-client-context-for-cluster-admin-access" name="configure-client-context-for-cluster-admin-access"></a>
## Configure client context for cluster admin access

The installer creates a `kubeconfig` file for each cluster, we are going to
merge them in the same file so we can use that file later with `kubefedctl`
tool. As an example, if you use the `--dir` option to create cluster1 within a
directory called `cluster1`, the kubeconfig will be in
`cluster1/admin/kubeconfig`.

First, we will rename the `admin` context and credentials of each cluster, then
merge the two kubeconfig files.

~~~sh
sed -i 's/admin/cluster1/g' cluster1/auth/kubeconfig

sed -i 's/admin/cluster2/g' cluster2/auth/kubeconfig

export KUBECONFIG=cluster1/auth/kubeconfig:cluster2/auth/kubeconfig

oc config view --flatten > /path/to/composed-kubeconfig

export KUBECONFIG=/path/to/composed-kubeconfig
oc config use-context cluster1
~~~

Now, our current client context is `system:admin` in `cluster1`. The
following commands assume this is the active context:

~~~sh
$ oc config current-context
cluster1
$ oc whoami
system:admin
~~~

The presence and unique naming of the client contexts are important because the
`kubefedctl` tool uses them to manage cluster registration, and they are
referenced by context name.

<a id="markdown-deploy-federation" name="deploy-federation"></a>
## Deploy Federation

Federation member clusters do not require KubeFed to be installed on them, but
for convenience, we will use one of the clusters (`cluster1`) to host
the KubeFed control plane.

In order to deploy the operator, we are going to use `Operator Hub` within the OCP4 Web Console.

The KubeFed operator supports two modes of operation: namespace scoped and
cluster scoped. This guide will walk through federating all namespaces through cluster scoped KubeFed.
There is also a guide to [namespace scoped KubeFed for OCP 4](README-ocp4.md)

1. Login into `cluster1` web console as `kubeadmin` user.
   1. Login details are reported by the installer in the file `auth/kubeadmin-password`.
2. Install KubeFed from `Operator Hub`.
   1. On the left panel click `Catalog -> Operator Hub`.
   2. Select `KubeFed` from operator list.
   3. If a warning about use of Community Operators is shown click `Continue`.
   4. Click `Install`.
   5. Under `Installation Method`, leave the selection on the default, `All namespaces on the cluster`.
   6. Click `Subscribe`.
3. Check the Operator Subscription status.
   1. On the left panel click `Catalog -> Operator Management`.
   2. Click `Operator Subscriptions` tab.
   3. Ensure the `Status` is "Up to date" for the `kubefed-operator` subscription.
4. Create a KubeFed resource to instantiate the KubeFed controller.
   1. On the left panel click `Catalog -> Installed Operators`.
   2. Click `Kubefed Operator`.
   3. Under `Provided APIs`, find `KubeFed`, and click `Create New`.
   4. Change the `spec: scope:` from `Namespaced` to `Cluster`.
   4. Note the namespace for the operator and KubeFed CR, `openshift-operators`, and click `Create`.

If everything works as expected, there should be a kubefed-controller-manager
Deployment with two pods running in `openshift-operators`.

~~~sh
oc --context=cluster1 -n openshift-operators get pods

NAME                                          READY   STATUS    RESTARTS   AGE
kubefed-controller-manager-67d5d5cc99-j9zh9   1/1     Running   0          1m
kubefed-controller-manager-67d5d5cc99-s59gx   1/1     Running   0          1m
kubefed-operator-694c8f9cdc-9pc5z             1/1     Running   0          2m

~~~

Now we are going to enable some of the federated types needed for our demo
application. You can watch as FederatedTypeConfig resources are created for
each type by visiting the `All Instances` tab of the `Kubefed Operator` under
`Catalog -> Installed Operators`.

~~~sh
for type in namespaces secrets serviceaccounts services configmaps deployments.apps
do
    kubefedctl enable $type --kubefed-namespace openshift-operators
done
~~~

<a id="markdown-register-the-clusters" name="register-the-clusters"></a>
## Register the clusters

Verify that there are no clusters yet (but note
that you can already reference the CRDs for federated clusters):

~~~sh
oc get kubefedclusters -n openshift-operators

No resources found.
~~~

Now use the `kubefedctl` tool to register (*join*) the two clusters:

~~~sh
kubefedctl join cluster1 \
            --host-cluster-context cluster1 \
            --cluster-context cluster1 \
            --kubefed-namespace=openshift-operators \
            --v=2
kubefedctl join cluster2 \
            --host-cluster-context cluster1 \
            --cluster-context cluster2 \
            --kubefed-namespace=openshift-operators \
            --v=2
~~~

Note that the names of the clusters (`cluster1` and `cluster2`) in the commands
above are a reference to the contexts configured in the `oc` client. For this
process to work as expected you need to make sure that the [client
contexts](#configure-client-context-for-cluster-admin-access) have been
properly configured with the right access levels and context names. The
`--cluster-context` option for `kubefedctl join` can be used to override the
reference to the client context configuration. When the option is not present,
`kubefedctl` uses the cluster name to identify the client context.

Verify that the federated clusters are registered and in a ready state (this
can take a moment):

~~~sh
oc -n openshift-operators get kubefedclusters 

NAME       READY   AGE
cluster1   True    2m
cluster2   True    2m
~~~

<a id="markdown-example-application" name="example-application"></a>
# Example application

Now that we have kubefed installed, let’s deploy an example app in both
clusters through the kubefed control plane.

First, create a test namespace to hold the example application:

~~~sh
oc create ns test-namespace
~~~

Next, add the test-namespace to KubeFed using the federate command:

~~~sh
kubefedctl --kubefed-namespace openshift-operators federate namespace test-namespace
~~~

Verify that our test-namespace is present in both clusters now:

~~~sh
oc --context=cluster1 get ns | grep test-namespace
oc --context=cluster2 get ns | grep test-namespace

test-namespace                 Active    2m
test-namespace                 Active    1m
~~~

The container image we will use for our example application (nginx) requires the
ability to choose its user id. Configure the clusters to grant that privilege:

~~~sh
for c in cluster1 cluster2; do
    oc --context ${c} \
        adm policy add-scc-to-user anyuid \
        system:serviceaccount:test-namespace:default
done
~~~

<a id="markdown-deploy-the-application" name="deploy-the-application"></a>
## Deploy the application

The sample application includes the following resources:

-   A [Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) of an nginx web server.
-   A [Service](https://kubernetes.io/docs/concepts/services-networking/service/) of type NodePort for nginx.
-   A sample [ConfigMap](https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/), [Secret](https://kubernetes.io/docs/concepts/configuration/secret/) and [ServiceAccount](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/). These are not actually used by
    the sample application (static nginx) but are included to illustrate how
    Kubefed would assist with more complex applications.

The [sample-app directory](./sample-app) contains definitions to deploy these resources. For each of them there is a resource template and a placement policy, and some of
them also have overrides. For example: the [sample nginx deployment template](./sample-app/federateddeployment.yaml)
specifies 3 replicas, but there is also an override that sets the replicas to 5
on `cluster2`.

Instantiate all these federated resources:

~~~sh
oc apply -R -f sample-app
~~~

<a id="markdown-verify-that-the-application-is-running" name="verify-that-the-application-is-running"></a>
## Verify that the application is running

Verify that the various resources have been deployed in both clusters according
to their respective placement policies and cluster overrides:

~~~sh
for resource in configmaps secrets deployments services; do
    for cluster in cluster1 cluster2; do
        echo ------------ ${cluster} ${resource} ------------
        oc --context=${cluster} -n test-namespace get ${resource}
    done
done
~~~

Verify that the application can be accessed:

~~~sh
for cluster in cluster1 cluster2; do
  echo ------------ ${cluster} ------------
  oc --context=${cluster} -n test-namespace expose service test-service
  url="http://$(oc --context=${cluster} -n test-namespace get route test-service -o jsonpath='{.spec.host}')"
  curl -I $url
done
~~~

<a id="markdown-modify-placement" name="modify-placement"></a>
## Modify placement

Now modify the `test-deployment` federated deployment placement policy to remove `cluster2`, leaving it
only active on `cluster1`:

~~~sh
oc -n test-namespace patch federateddeployment test-deployment \
    --type=merge -p '{"spec":{"placement":{"clusters":[{"name": "cluster1"}]}}}'
~~~

Observe how the federated deployment is now only present in `cluster1`:

~~~sh
for cluster in cluster1 cluster2; do
    echo ------------ ${cluster} deployments ------------
    oc --context=${cluster} -n test-namespace get deployments
done
~~~

Now add `cluster2` back to the federated deployment placement:

~~~sh
oc -n test-namespace patch federateddeployment test-deployment \
    --type=merge -p '{"spec":{"placement":{"clusters": [{"name": "cluster1"}, {"name": "cluster2"}]}}}'
~~~

And verify that the federated deployment was deployed on both clusters again:

~~~sh
for cluster in cluster1 cluster2; do
    echo ------------ ${cluster} deployments ------------
    oc --context=${cluster} -n test-namespace get deployments
done
~~~

<a id="markdown-clean-up" name="clean-up"></a>
# Clean up

To clean up the test application run:

~~~sh
oc delete -R -f sample-app
for cluster in cluster1 cluster2; do
  oc --context=${cluster} -n test-namespace delete route test-service
done
~~~

This leaves the two clusters with federation deployed. If you want to disable federation:

1. Login into `cluster1` web console as `kubeadmin` user
   1. Login details were reported by the installer
2. Ensure the active project is `test-namespace`
3. Delete the CVS (Cluster Service Version)
   1. On the left panel click `Catalog -> Installed Operators`
   2. Click the three dots icon on the federation entry
   3. Click `Delete Cluster Service Version`

<a id="markdown-whats-next" name="whats-next"></a>
# What’s next?

This walkthrough does not go into detail about the components and resources involved
in cluster federation. Feel free to explore the repository to review the YAML files
that configure KubeFed and deploy the sample application. See also the upstream
KubeFed repository and its [user guide](https://github.com/kubernetes-sigs/kubefed/blob/master/docs/userguide.md), on which this guide is based.

Beyond that: More advanced aspects of cluster federation
like managing ingress traffic or storage rely on supporting infrastructure for
the clusters will be topics for more advanced guides.
