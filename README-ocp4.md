**Table of Contents**

<!-- TOC depthFrom:1 insertAnchor:true orderedList:true -->

1. [Introduction](#introduction)
2. [Pre-requisites](#pre-requisites)
    1. [Install the kubefed2 binary](#install-the-kubefed2-binary)
    2. [Download the example code](#download-the-example-code)
3. [Federation deployment](#federation-deployment)
    1. [Create the two OpenShift clusters](#create-the-two-openshift-clusters)
        1. [Configure client context for cluster admin access](#configure-client-context-for-cluster-admin-access)
    2. [Deploy Federation](#deploy-federation)
    3. [Register the clusters in the cluster registry](#register-the-clusters-in-the-cluster-registry)
4. [Example application](#example-application)
    1. [Deploy the application](#deploy-the-application)
    2. [Verify that the application is running](#verify-that-the-application-is-running)
    3. [Modify placement](#modify-placement)
5. [Clean up](#clean-up)
6. [What’s next?](#whats-next)

<!-- /TOC -->

<a id="markdown-introduction" name="introduction"></a>
# Introduction

This demo is a simple deployment of [Federation v2 Operator](https://operatorhub.io/operator/federation.v0.0.6) on two OpenShift
clusters. A sample application is deployed to both clusters through the
federation controller.

<a id="markdown-pre-requisites" name="pre-requisites"></a>
# Prerequisites

The Federation Operator requires at least one [OpenShift Container Platform](https://www.openshift.com/) 4.0 cluster.

This walkthrough will use 2 OCP 4.0 clusters deployed using the [developer preview on AWS](https://cloud.openshift.com/clusters/install).

<a id="markdown-install-the-kubefed2-binary" name="install-the-kubefed2-binary"></a>
## Install the kubefed2 binary

The `kubefed2` tool manages federated cluster registration. Download the
v0.0.7 release and unpack it into a directory in your PATH (the
example uses `$HOME/bin`):

~~~sh
curl -LOs https://github.com/kubernetes-sigs/federation-v2/releases/download/v0.0.7/kubefed2.tar.gz
tar xzf kubefed2.tar.gz -C ~/bin
rm -f kubefed2.tar.gz
~~~

Verify that `kubefed2` is working:

~~~sh
kubefed2 version

kubefed2 version: version.Info{Version:"v0.0.7", GitCommit:"83b778b6d92a7929efb7687d3d3d64bf0b3ad3bc", GitTreeState:"clean", BuildDate:"2019-03-19T18:40:46Z", GoVersion:"go1.11.2", Compiler:"gc", Platform:"linux/amd64"}
~~~

<a id="markdown-download-the-example-code" name="download-the-example-code"></a>
## Download the example code

Clone the demo code to your local machine:

~~~sh
git clone --recurse-submodules https://github.com/openshift/federation-dev.git
cd federation-dev/
~~~

<a id="markdown-federation-deployment" name="federation-deployment"></a>
# Federation deployment

<a id="markdown-create-the-two-openshift-clusters" name="create-the-two-openshift-clusters"></a>
## Create the two OpenShift clusters

Follow the [developer preview instructions](https://cloud.openshift.com/clusters/install) for installing two OpenShift 4.0 clusters on AWS.

Once both clusters are up and running, we are going to merge the Kubernetes configurations files so we have a connection to both clusters using the same Kubeconfig file.

<a id="markdown-configure-client-context-for-cluster-admin-access" name="configure-client-context-for-cluster-admin-access"></a>
## Configure client context for cluster admin access

The installer has created a `kubeconfig` file for each cluster, we are going to merge them in the same file so we can use that file later with `kubefed2` tool.

First, we will rename the `admin` context and then we will rename the admin user so when we merge the two kubeconfig files both admin users are present.

~~~sh
export KUBECONFIG=/path/to/cluster1/kubeconfig
oc config rename-context admin cluster1
sed -i 's/admin/cluster1/g' $KUBECONFIG

export KUBECONFIG=/path/to/cluster2/kubeconfig
oc config rename-context admin cluster2
sed -i 's/admin/cluster2/g' $KUBECONFIG

export KUBECONFIG=/path/to/cluster1/kubeconfig:/path/to/cluster2/kubeconfig
oc config view --flatten > /path/to/composed-kubeconfig

export KUBECONFIG=/path/to/composed-kubeconfig
oc config use-context cluster1
~~~

After this our current client context is `system:admin` in `cluster1`. The
following commands assume this is the active context:

~~~sh
$ oc config current-context
cluster1
$ oc whoami
system:admin
~~~

The presence and unique naming of the client contexts are important because the `kubefed2` tool uses them to manage cluster registration, and they are referenced by context name.

<a id="markdown-deploy-federation" name="deploy-federation"></a>
## Deploy Federation

Federation target clusters do not require federation to be installed on them at
all, but for convenience, we will use one of the clusters (`cluster1`) to host
the federation control plane.

At the moment, the Federation V2 Operator only works in namespace-scoped mode, in the future cluster-scoped mode will be supported as well by the operator.

In order to deploy the operator, we are going to use `Operator Hub` within the OCP4 WebUI.

1. Login into `cluster1` web console as `kubeadmin` user
   1. Login details were reported by the installer
2. Create the namespace to be federated         
   1. On the left panel click `Home -> Projects`
   2. Click `Create Project`
   3. Name it `test-namespace`
   4. Click `Create`
3. Install Federation from `Operator Hub`
   1. On the left panel click `Catalog -> Operator Hub`
   2. Select `Federation` from operator list
   3. If a warning about use of Community Operators is shown click `Continue`
   3. Click `Install`
   4. Make sure `test-namespace` is selected as destination namespace
   5. Click `Subscribe`
4. Check the Operator Subscription status
   1. On the left panel click `Catalog -> Operator Management`
   2. Click `Operator Subscriptions` tab
   3. Ensure the `Status` is "Up to date" for the `federation` subscription

If everything is okay, we should have the federation controller running in the namespace  `test-namespace`.

~~~sh
oc --context=cluster1 -n test-namespace get pods

NAME                                             READY     STATUS    RESTARTS   AGE
federation-controller-manager-744f57ccff-q4f6k   1/1       Running   0          28m
~~~

Now we are going to enable some of the federated types needed for our demo application

~~~sh
for type in namespaces secrets serviceaccounts services configmaps deployments.apps
do
    kubefed2 enable $type --federation-namespace test-namespace --registry-namespace test-namespace
done
~~~

**Warning**:

If you get this error while enabling new types, you are hitting this [bug](https://bugzilla.redhat.com/show_bug.cgi?id=1692869) (will be fixed in 0.0.8 release):

```
F0410 15:19:13.669674   22623 enable.go:112] error: Error initializing validation schema accessor: Error loading openapi schema: SchemaError(io.k8s.federation.types.v1alpha1.FederatedDeployment.spec.retainReplicas): Unknown primitive type: "bool"
```

<a id="markdown-register-the-clusters-in-the-cluster-registry" name="register-the-clusters-in-the-cluster-registry"></a>
## Register the clusters in the cluster registry

Verify that there are no clusters in the registry yet (but note
that you can already reference the CRDs for federated clusters):

~~~sh
oc get federatedclusters -n test-namespace
oc get clusters --all-namespaces

No resources found.
~~~

Now use the `kubefed2` tool to register (*join*) the two clusters:

~~~sh
kubefed2 join cluster1 \
            --host-cluster-context cluster1 \
            --cluster-context cluster1 \
            --add-to-registry \
            --v=2 \
            --federation-namespace=test-namespace \
            --registry-namespace=test-namespace \
            --limited-scope=true
kubefed2 join cluster2 \
            --host-cluster-context cluster1 \
            --cluster-context cluster2 \
            --add-to-registry \
            --v=2 \
            --federation-namespace=test-namespace \
            --registry-namespace=test-namespace \
            --limited-scope=true
~~~

Note that the names of the clusters (`cluster1` and `cluster2`) in the commands above are a refence to the contexts configured in the `oc` client. For this process to work as expected you need to make sure that the [client contexts](#configure-client-context-for-cluster-admin-access) have been properly configured with the right access levels and context names. The `--cluster-context` option for `kubefed2 join` can be used to override the refernce to the client context configuration. When the option is not present, `kubefed2` uses the cluster name to identify the client context.

Verify that the federated clusters are registered and in a ready state (this
can take a moment):

~~~sh
oc describe federatedclusters -n test-namespace

Name:         cluster1
Namespace:    test-namespace
Labels:       <none>
Annotations:  <none>
API Version:  core.federation.k8s.io/v1alpha1
Kind:         FederatedCluster
Metadata:
  Creation Timestamp:  2019-03-25T19:38:11Z
  Generation:          1
  Resource Version:    111057
  Self Link:           /apis/core.federation.k8s.io/v1alpha1/namespaces/test-namespace/federatedclusters/cluster1
  UID:                 8612a72f-4f35-11e9-953c-02a016278e96
Spec:
  Cluster Ref:
    Name:  cluster1
  Secret Ref:
    Name:  cluster1-2mj4t
Status:
  Conditions:
    Last Probe Time:       2019-03-25T19:39:37Z
    Last Transition Time:  2019-03-25T19:38:17Z
    Message:               /healthz responded with ok
    Reason:                ClusterReady
    Status:                True
    Type:                  Ready
  Region:                  us-east-1
  Zone:                    us-east-1a
Events:                    <none>


Name:         cluster2
Namespace:    test-namespace
Labels:       <none>
Annotations:  <none>
API Version:  core.federation.k8s.io/v1alpha1
Kind:         FederatedCluster
Metadata:
  Creation Timestamp:  2019-03-25T19:38:45Z
  Generation:          1
  Resource Version:    111058
  Self Link:           /apis/core.federation.k8s.io/v1alpha1/namespaces/test-namespace/federatedclusters/cluster2
  UID:                 9a762e4d-4f35-11e9-9909-0eebed9414aa
Spec:
  Cluster Ref:
    Name:  cluster2
  Secret Ref:
    Name:  cluster2-mch2g
Status:
  Conditions:
    Last Probe Time:       2019-03-25T19:39:37Z
    Last Transition Time:  2019-03-25T19:38:57Z
    Message:               /healthz responded with ok
    Reason:                ClusterReady
    Status:                True
    Type:                  Ready
  Region:                  us-east-1
  Zone:                    us-east-1a
Events:                    <none>
~~~

<a id="markdown-example-application" name="example-application"></a>
# Example application

Now that we have federation installed, let’s deploy an example app in both
clusters through the federation control plane.

Verify that our test-namespace is present in both clusters now:

~~~sh
oc --context=cluster1 get ns | grep test-namespace
oc --context=cluster2 get ns | grep test-namespace

test-namespace                 Active    54s
test-namespace                 Active    55s
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
    federation would assist with more complex applications.

The [sample-app directory](./sample-app) contains definitions to deploy these resources. For
each of them there is a resource template and a placement policy, and some of
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
  echo ------------ ${cluster} test ------------
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
    --type=merge -p '{"spec":{"placement":{"clusterNames": ["cluster1"]}}}'
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
    --type=merge -p '{"spec":{"placement":{"clusterNames": ["cluster1", "cluster2"]}}}'
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
that configure Federation and deploy the sample application. See also the upstream
federation-v2 repo and its [user guide](https://github.com/kubernetes-sigs/federation-v2/blob/master/docs/userguide.md), on which this guide is based.

Beyond that: More advanced aspects of cluster federation
like managing ingress traffic or storage rely on supporting infrastructure for
the clusters will be topics for more advanced guides.
