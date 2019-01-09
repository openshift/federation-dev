**Table of Contents**

<!-- TOC depthFrom:1 insertAnchor:true orderedList:true -->

1. [Introduction](#introduction)
2. [Pre-requisites](#pre-requisites)
    1. [Install the CDK](#install-the-cdk)
        1. [Configure and validate the CDK](#configure-and-validate-the-cdk)
    2. [Install the kubefed2 binary](#install-the-kubefed2-binary)
    3. [Download the example code](#download-the-example-code)
3. [Federation deployment](#federation-deployment)
    1. [Create the two OpenShift clusters](#create-the-two-openshift-clusters)
        1. [Configure client context for cluster admin access](#configure-client-context-for-cluster-admin-access)
    2. [Deploy Federation](#deploy-federation)
    3. [Register the clusters in the cluster registry](#register-the-clusters-in-the-cluster-registry)
4. [Example application](#example-application)
    1. [Create a federated namespace](#create-a-federated-namespace)
    2. [Deploy the application](#deploy-the-application)
    3. [Verify that the application is running](#verify-that-the-application-is-running)
    4. [Modify placement](#modify-placement)
5. [Clean up](#clean-up)
6. [What’s next?](#whats-next)

<!-- /TOC -->

<a id="markdown-introduction" name="introduction"></a>
# Introduction

This demo is a simple deployment of [Kubernetes Federation v2](https://github.com/kubernetes-sigs/federation-v2) on two OpenShift
clusters. A sample application is deployed to both clusters through the
federation controller.

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

minishift v1.27.0+5981f99
CDK v3.7.0-1
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

<a id="markdown-install-the-kubefed2-binary" name="install-the-kubefed2-binary"></a>
## Install the kubefed2 binary

The `kubefed2` tool manages federated cluter registration. Download the
0.0.2-rc.1 release and unpack it into a diretory in your PATH (the
example uses `$HOME/bin`):

~~~sh
curl -LOs https://github.com/kubernetes-sigs/federation-v2/releases/download/v0.0.4/kubefed2.tar.gz
tar xzf kubefed2.tar.gz -C ~/bin
rm -f kubefed2.tar.gz
~~~

Verify that `kubefed2` is working:

~~~sh
kubefed2 version

kubefed2 version: version.Info{Version:"v0.0.4", GitCommit:"2cdf5d37240d9b8b33e2715deb75fbb7f9e003ad", GitTreeState:"clean", BuildDate:"2018-12-10T23:03:18Z", GoVersion:"go1.10.3", Compiler:"gc", Platform:"linux/amd64"}
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

Cluster-wide federation needs cluster administrator privileges, so switch the
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

The presence and naming of the client contexts is important because the `kubefed2` tool uses them to manage cluster registration, and they are referenced by context name.

<a id="markdown-deploy-federation" name="deploy-federation"></a>
## Deploy Federation

Federation target clusters do not require federation to be installed on them at
all, but for convenience we will use one of the clusters (`cluster1`) to host
the federation control plane.

The federation controller also needs elevated privileges. Grant cluster-admin
level to the default service account of the federation-system project (the
project itself will be created soon):

~~~sh
oc create clusterrolebinding federation-admin \
          --clusterrole="cluster-admin" \
          --serviceaccount="federation-system:default"
~~~

Change directory to Federation V2 repo (The repository submodule is already pointing to `tag/v0.0.4`):

~~~sh
cd federation-v2/
~~~

Create the required namespaces:

~~~sh
oc create ns federation-system
oc create ns kube-multicluster-public
~~~

Deploy the federation control plane and its associated Custom Resource Definitions ([CRDs](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/)):

~~~sh
oc -n federation-system apply --validate=false -f hack/install-latest.yaml
~~~

Deploy the [cluster registry](https://github.com/kubernetes/cluster-registry) and the namespace where clusters are registered
(`kube-multicluster-public`):

~~~sh
oc apply --validate=false -f vendor/k8s.io/cluster-registry/cluster-registry-crd.yaml
~~~

The above created:

-   The federation CRDs
-   A [StatefulSet](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/) that deploys the federation controller, and a [Service](https://kubernetes.io/docs/concepts/services-networking/service/) for it.

Now deploy the CRDs that determine which Kubernetes resources are federated across
the clusters:

~~~sh
for filename in ./config/federatedirectives/*.yaml
do
  kubefed2 federate enable -f "${filename}" --federation-namespace=federation-system
done
~~~

After a short while the federation controller manager pod is running:

~~~sh
oc get pod -n federation-system

NAME                              READY     STATUS    RESTARTS   AGE
federation-controller-manager-0   1/1       Running   0          31s
~~~

<a id="markdown-register-the-clusters-in-the-cluster-registry" name="register-the-clusters-in-the-cluster-registry"></a>
## Register the clusters in the cluster registry

Verify that there are no clusters in the registry yet (but note
that you can already reference the CRDs for federated clusters):

~~~sh
oc get federatedclusters -n federation-system
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
            --federation-namespace=federation-system
kubefed2 join cluster2 \
            --host-cluster-context cluster1 \
            --cluster-context cluster2 \
            --add-to-registry \
            --v=2 \
            --federation-namespace=federation-system
~~~

Note that the names of the clusters (`cluster1` and `cluster2`) in the commands above are a refence to the contexts configured in the `oc` client. For this to work as expected you need to make sure that the [client contexts](#configure-client-context-for-cluster-admin-access) have been properly configured with the right access levels and context names. The `--cluster-context` option for `kubefed2 join` can be used to override the refernce to the client context configuration. When the option is not present, `kubefed2` uses the cluster name to identify the client context.

Verify that the federated clusters are registered and in a ready state (this
can take a moment):

~~~sh
oc describe federatedclusters -n federation-system

Name:         cluster1
Namespace:    federation-system
Labels:       <none>
Annotations:  <none>
API Version:  core.federation.k8s.io/v1alpha1
Kind:         FederatedCluster
Metadata:
  Creation Timestamp:  2018-12-20T16:40:54Z
  Generation:          1
  Resource Version:    7638
  Self Link:           /apis/core.federation.k8s.io/v1alpha1/namespaces/federation-system/federatedclusters/cluster1
  UID:                 04bd001a-0476-11e9-aa7e-525400169746
Spec:
  Cluster Ref:
    Name:  cluster1
  Secret Ref:
    Name:  cluster1-7954h
Status:
  Conditions:
    Last Probe Time:       2018-12-20T16:41:01Z
    Last Transition Time:  2018-12-20T16:41:01Z
    Message:               /healthz responded with ok
    Reason:                ClusterReady
    Status:                True
    Type:                  Ready
Events:                    <none>


Name:         cluster2
Namespace:    federation-system
Labels:       <none>
Annotations:  <none>
API Version:  core.federation.k8s.io/v1alpha1
Kind:         FederatedCluster
Metadata:
  Creation Timestamp:  2018-12-20T16:40:55Z
  Generation:          1
  Resource Version:    7643
  Self Link:           /apis/core.federation.k8s.io/v1alpha1/namespaces/federation-system/federatedclusters/cluster2
  UID:                 0579c27b-0476-11e9-aa7e-525400169746
Spec:
  Cluster Ref:
    Name:  cluster2
  Secret Ref:
    Name:  cluster2-6psnp
Status:
  Conditions:
    Last Probe Time:       2018-12-20T16:41:01Z
    Last Transition Time:  2018-12-20T16:41:01Z
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

<a id="markdown-create-a-federated-namespace" name="create-a-federated-namespace"></a>
## Create a federated namespace

Create a test project (`test-namespace`) and add a federated placement policy
for it:

~~~sh
cat << EOF | oc create -f -
apiVersion: v1
kind: List
items:
- apiVersion: v1
  kind: Namespace
  metadata:
    name: test-namespace
- apiVersion: primitives.federation.k8s.io/v1alpha1
  kind: FederatedNamespacePlacement
  metadata:
    name: test-namespace
    namespace: test-namespace
  spec:
    clusterNames:
    - cluster1
    - cluster2
EOF
~~~

Verify that the namespace is present in both clusters now:

~~~sh
oc --context=cluster1 get ns | grep test
oc --context=cluster2 get ns | grep test

test-namespace                 Active    7s
test-namespace                 Active    7s
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
them also have overrides. For example: the [sample nginx deployment template](./sample-app/federateddeployment-template.yaml)
specifies 3 replicas, but there is also [an override](./sample-app/federateddeployment-override.yaml) that sets the replicas to 5
on `cluster2`.

Instantiate all these federated resources:

~~~sh
cd ../
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
host=$(oc whoami --show-server | sed -e 's#https://##' -e 's/:8443//')
port=$(oc get svc -n test-namespace test-service -o jsonpath={.spec.ports[0].nodePort})

curl -I $host:$port
~~~

<a id="markdown-modify-placement" name="modify-placement"></a>
## Modify placement

Now modify the test namespace placement policy to remove `cluster2`, leaving it
only active on `cluster1`:

~~~sh
oc -n test-namespace patch federatednamespaceplacement test-namespace \
    --type=merge -p '{"spec":{"clusterNames": ["cluster1"]}}'
~~~

Observe how the federated resources are now only present in `cluster1`:

~~~sh
for resource in configmaps secrets deployments services; do
    for cluster in cluster1 cluster2; do
        echo ------------ ${cluster} ${resource} ------------
        oc --context=${cluster} -n test-namespace get ${resource}
    done
done
~~~

Now add `cluster2` back to the federated namespace placement:

~~~sh
oc -n test-namespace patch federatednamespaceplacement test-namespace \
    --type=merge -p '{"spec":{"clusterNames": ["cluster1", "cluster2"]}}'
~~~

And verify that the federated resources were deployed on both clusters again:

~~~sh
for resource in configmaps secrets deployments services; do
    for cluster in cluster1 cluster2; do
        echo ------------ ${cluster} ${resource} ------------
        oc --context=${cluster} -n test-namespace get ${resource}
    done
done
~~~

<a id="markdown-clean-up" name="clean-up"></a>
# Clean up

To clean up only the test application run:

~~~sh
oc delete ns test-namespace
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
federation-v2 repo and its [user guide](https://github.com/kubernetes-sigs/federation-v2/blob/master/docs/userguide.md), on which this guide is based.

Beyond that: the CDK/minishift provides us with a quick and easy environment for
testing, but it has limitations. More advanced aspects of cluster federation
like managing ingress traffic or storage rely on supporting infrastructure for
the clusters that is not available in minishift. These will be topics for
more advanced guides.
