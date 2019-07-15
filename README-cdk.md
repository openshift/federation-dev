**Table of Contents**

<!-- TOC depthFrom:1 insertAnchor:true orderedList:true -->

- [Introduction](#introduction)
- [Pre-requisites](#pre-requisites)
  - [Install the CDK](#install-the-cdk)
    - [Configure and validate the CDK](#configure-and-validate-the-cdk)
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
- [Known Issues](#known-issues)

<!-- /TOC -->

<a id="markdown-introduction" name="introduction"></a>
# Introduction

**Note** //This document is undergoing revisions with the v0.1.0 release of KubeFed which takes the Federation Operator and KubeFed project into Beta status.//

This demo is a simple deployment of [Federation Operator](https://operatorhub.io/operator/alpha/federation.v0.0.10) on two OpenShift
clusters. A sample application is deployed to both clusters through the Federation controller.

<a id="markdown-pre-requisites" name="pre-requisites"></a>
# Pre-requisites

Federation requires an OpenShift 3.11 cluster and works on both [OKD](https://www.okd.io/) and [OpenShift Container Platform](https://www.openshift.com/) (OCP).

This walkthrough will use 2 all-in-one OCP clusters deployed using the
 [Red Hat Container
 Development Kit](https://developers.redhat.com/products/cdk/overview/) (CDK), a downstream version of [minishift](https://github.com/minishift/minishift) that uses OCP
 instead of OKD.

<a id="markdown-install-the-cdk" name="install-the-cdk"></a>
## Install the CDK

Download the CDK from the [CDK download page](https://developers.redhat.com/products/cdk/download/) by clicking on the link for your
platform (Linux / MacOS / Windows), and put the binary in your PATH (for example
in `~/bin`) renaming it to `cdk`.

**Note**: this guide uses `cdk` as the name of the binary instead of
`minishift`. This makes it possible to have both minishift and the CDK installed
on your system. Be aware though that configuration directory is the same for
both though (`~/.minishift`).

**Note**: the *download* button in the page attempts to auto-detect the most
appropriate version, but the auto-detection has some known issues. It is
recommended that you use the download the link for your platform instead
of the *download* button.

**Note**: the steps below will create a few entries in the `kubectl` / `oc` client
configuration file (`~/.kube/config`). If you have an existing client
configuration file that you want to preserve unmodified it is advisable to make
a backup copy before starting.

<a id="markdown-configure-and-validate-the-cdk" name="configure-and-validate-the-cdk"></a>
### Configure and validate the CDK

Your system should have the CDK configured and ready to use with your
preferred VM driver and the `oc` client to interact with them. You can use the
`oc` client [bundled with the CDK](https://access.redhat.com/documentation/en-us/red_hat_container_development_kit/3.6/html-single/getting_started_guide/#using_the_openshift_client_binary_oc).

The steps in this walkthrough were tested with:

~~~sh
cdk version

minishift v1.31.0+d06603e
CDK v3.8.0-2
~~~

Initialize the CDK:

~~~sh
cdk setup-cdk
~~~

Configure username and password for the VMs to register and access content in
the registry:

~~~sh
export MINISHIFT_USERNAME='<RED_HAT_USERNAME>'
read -s -p 'Password: ' MINISHIFT_PASSWORD
export MINISHIFT_PASSWORD
~~~

<a id="markdown-install-the-kubefedctl-binary" name="install-the-kubefedctl-binary"></a>
## Install the kubefedctl binary

The `kubefedctl` tool manages federated cluster registration. Download the
v0.0.10 release and unpack it into a directory in your PATH (the
example uses `$HOME/bin`):

~~~sh
curl -LOs https://github.com/kubernetes-sigs/kubefed/releases/download/v0.0.10/kubefedctl.tgz
tar xzf kubefedctl.tgz -C ~/bin
rm -f kubefedctl.tgz
~~~

Verify that `kubefedctl` is working:

~~~sh
kubefedctl version

kubefedctl version: version.Info{Version:"v0.0.10-dirty", GitCommit:"71d233ede685707df554ef653e06bf7f0229415c", GitTreeState:"dirty", BuildDate:"2019-05-06T22:30:31Z", GoVersion:"go1.11.2", Compiler:"gc", Platform:"linux/amd64"}
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

Start two CDK/minishift clusters with OCP 3.11 called `cluster1` and
`cluster2`. Note that these cluster names are referenced throughout the
walkthrough, so it's recommended that you adhere to them:

~~~sh
cdk start --profile cluster1 --openshift-version v3.11.16
cdk start --profile cluster2 --openshift-version v3.11.16
~~~

Each cdk invocation will generate output as it progresses and will
conclude with instructions on how to access each cluster using a browser
or the command line:

    -- Starting profile 'cluster1'
    -- Check if deprecated options are used ... OK
    -- Checking if https://mirror.openshift.com is reachable ... OK
    [output truncated]
    OpenShift server started.
    
    The server is accessible via web console at:
        https://192.168.42.184:8443
    
    You are logged in as:
        User:     developer
        Password: <any value>
    
    To login as administrator:
        oc login -u system:admin

By default the CDK enables a few minishift add-ons, including the
[anyuid addon](https://github.com/minishift/minishift/blob/master/addons/anyuid/anyuid.addon)
which allows pods to run as the user ID of their choice. The
[example application](#example-application) below makes use of that privilege.

<a id="markdown-configure-client-context-for-cluster-admin-access" name="configure-client-context-for-cluster-admin-access"></a>
### Configure client context for cluster admin access

In order to use the `oc` client bundled with the CDK, run this to add it to
your `$PATH`:

~~~sh
eval $(cdk oc-env)
~~~

We need cluster administrator privileges, so switch the
`oc` client contexts to use the `system:admin` account instead of the default
unprivileged `developer` user:

~~~sh
oc config use-context cluster2
oc login -u system:admin
oc config rename-context cluster2 cluster2-developer
oc config rename-context $(oc config current-context) cluster2
~~~

And the same for `cluster1`:

~~~sh
oc config use-context cluster1
oc login -u system:admin
oc config rename-context cluster1 cluster1-developer
oc config rename-context $(oc config current-context) cluster1
~~~

After this our current client context is for `system:admin` in `cluster1`. The
following commands assume this is the active context:

~~~sh
oc config current-context
oc whoami

cluster1
system:admin
~~~

The presence and naming of the client contexts is important because the `kubefedctl` tool uses them to manage cluster registration, and they are referenced by context name.

<a id="markdown-deploy-federation" name="deploy-federation"></a>
## Deploy Federation

Federation target clusters do not require federation to be installed on them at
all, but for convenience we will use one of the clusters (`cluster1`) to host
the federation control plane.

At the moment, the Federation Operator only works in namespace-scoped mode, in the future cluster-scoped mode will be supported as well by the operator.

In order to deploy the operator, we are going to use `OLM`, so we will need to deploy `OLM` before deploying the federation operator.

~~~sh
oc create -f olm/01-olm.yaml
oc create -f olm/02-olm.yaml
~~~

Now that we have the `OLM` deployed, it is time to deploy the federation operator. We will create a new namespace `test-namespace` where the kubefed controller will be deployed.

Wait until all pods in namespace `olm` are running:

~~~sh
oc get pods -n olm

NAME                               READY     STATUS    RESTARTS   AGE
catalog-operator-bfc6fd7bc-xdwbs   1/1       Running   0          3m
olm-operator-787885c577-wmzxp      1/1       Running   0          3m
olm-operators-gmnk4                1/1       Running   0          3m
operatorhubio-catalog-gng4x        1/1       Running   0          3m
packageserver-7fc659d9cb-5qbw9     1/1       Running   0          2m
packageserver-7fc659d9cb-tl9gv     1/1       Running   0          2m
~~~

Then, create the kubefed subscription.

~~~sh
oc create -f olm/kubefed.yaml
~~~

After a short while the kubefed controller manager pod is running:

> **NOTE:** It can take up to a minute for the pod to appear

~~~sh
oc get pod -n test-namespace

NAME                              READY     STATUS    RESTARTS   AGE
federation-controller-manager-6bcf6c695f-mmnv6   1/1       Running   0          1m
~~~

Now we are going to enable some of the federated types needed for our demo application

~~~sh
for type in namespaces secrets serviceaccounts services configmaps deployments.apps
do
    kubefedctl enable $type --federation-namespace test-namespace 
done
~~~

<a id="markdown-register-the-clusters" name="register-the-clusters"></a>
## Register the clusters

Verify that there are no clusters yet (but note
that you can already reference the CRDs for federated clusters):

~~~sh
oc get federatedclusters -n test-namespace

No resources found.
~~~

Now use the `kubefedctl` tool to register (*join*) the two clusters:

~~~sh
kubefedctl join cluster1 \
            --host-cluster-context cluster1 \
            --cluster-context cluster1 \
            --add-to-registry \
            --v=2 \
            --federation-namespace=test-namespace
kubefedctl join cluster2 \
            --host-cluster-context cluster1 \
            --cluster-context cluster2 \
            --add-to-registry \
            --v=2 \
            --federation-namespace=test-namespace
~~~

Note that the names of the clusters (`cluster1` and `cluster2`) in the commands above are a reference to the contexts configured in the `oc` client. For this to work as expected you need to make sure that the [client contexts](#configure-client-context-for-cluster-admin-access) have been properly configured with the right access levels and context names. The `--cluster-context` option for `kubefedctl join` can be used to override the reference to the client context configuration. When the option is not present, `kubefedctl` uses the cluster name to identify the client context.

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
  Creation Timestamp:  2019-05-15T16:41:38Z
  Generation:          1
  Resource Version:    9108
  Self Link:           /apis/core.federation.k8s.io/v1alpha1/namespaces/test-namespace/federatedclusters/cluster1
  UID:                 4f139f4c-7730-11e9-b9cd-525400552436
Spec:
  Cluster Ref:
    Name:  cluster1
  Secret Ref:
    Name:  cluster1-nrnvf
Status:
  Conditions:
    Last Probe Time:       2019-05-15T16:42:05Z
    Last Transition Time:  2019-05-15T16:41:44Z
    Message:               /healthz responded with ok
    Reason:                ClusterReady
    Status:                True
    Type:                  Ready
Events:                    <none>


Name:         cluster2
Namespace:    test-namespace
Labels:       <none>
Annotations:  <none>
API Version:  core.federation.k8s.io/v1alpha1
Kind:         FederatedCluster
Metadata:
  Creation Timestamp:  2019-05-15T16:41:40Z
  Generation:          1
  Resource Version:    9110
  Self Link:           /apis/core.federation.k8s.io/v1alpha1/namespaces/test-namespace/federatedclusters/cluster2
  UID:                 506516c4-7730-11e9-b9cd-525400552436
Spec:
  Cluster Ref:
    Name:  cluster2
  Secret Ref:
    Name:  cluster2-zwz5b
Status:
  Conditions:
    Last Probe Time:       2019-05-15T16:42:05Z
    Last Transition Time:  2019-05-15T16:41:44Z
    Message:               /healthz responded with ok
    Reason:                ClusterReady
    Status:                True
    Type:                  Ready
Events:                    <none>
~~~

<a id="markdown-example-application" name="example-application"></a>
# Example application

Now that we have federation installed, let’s deploy an example app in both
clusters through the federation control plane.

Verify that the namespace is present in both clusters now:

~~~sh
oc --context=cluster1 get ns | grep test-namespace
oc --context=cluster2 get ns | grep test-namespace

test-namespace                 Active    4m
test-namespace                 Active    1m
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
    echo ------------ ${cluster} ------------
    host=$(oc --context $cluster whoami --show-server | sed -e 's#https://##' -e 's/:8443//')
    port=$(oc --context $cluster get svc -n test-namespace test-service -o jsonpath={.spec.ports[0].nodePort})
    curl -I $host:$port
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

To clean up only the test application run:

~~~sh
oc delete -R -f sample-app
~~~

This leaves the two clusters with federation deployed. If you want to remove everything run:

~~~sh
for cluster in cluster1 cluster2; do
    oc config delete-context ${cluster}-developer
    oc config delete-context ${cluster}
    cdk profile delete ${cluster}
done
~~~

Note that the `oc login` commands that were used to switch to the `system:admin` account might
have created additional entries in your `oc` client configuration (`~/.kube/config`).

<a id="markdown-whats-next" name="whats-next"></a>
# What’s next?

This walkthrough does not go into detail of the components and resources involved
in cluster federation. Feel free to explore the repository to review the YAML files
that configure Federation and deploy the sample application. See also the upstream
kubefed repository and its [user guide](https://github.com/kubernetes-sigs/kubefed/blob/master/docs/userguide.md), on which this guide is based.

Beyond that: the CDK/minishift proides us with a quick and easy environment for
testing, but it has limitations. More advanced aspects of cluster federation
like managing ingress traffic or storage rely on supporting infrastructure for
the clusters that is not available in minishift. These will be topics for
more advanced guides.

<a id="markdown-known-issues" name="known-issues"></a>
# Known Issues

One issue that has come up while working with this demo is a log entry generated once per minute per cluster over the lack of zone or region labels on the minishift nodes. The error is harmless, but may interfere with finding real issues in the federation-controller-manager logs. An example follows:

~~~
W0321 15:51:31.208448       1 controller.go:216] Failed to get zones and region for cluster cluster1: Zone name for node localhost not found. No label with key failure-domain.beta.kubernetes.io/zone
W0321 15:51:31.298093       1 controller.go:216] Failed to get zones and region for cluster cluster2: Zone name for node localhost not found. No label with key failure-domain.beta.kubernetes.io/zone
~~~

The work-around would be to go ahead and label the minishift nodes with some zone and region data, e.g.

~~~sh
oc --context=cluster1 label node localhost failure-domain.beta.kubernetes.io/region=minishift
oc --context=cluster2 label node localhost failure-domain.beta.kubernetes.io/region=minishift
oc --context=cluster1 label node localhost failure-domain.beta.kubernetes.io/zone=east
oc --context=cluster2 label node localhost failure-domain.beta.kubernetes.io/zone=west
~~~
