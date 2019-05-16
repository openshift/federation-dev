 # Federation Pacman
The files within this directory are used with the Federation operator to show
an application balancing and moving between OpenShift clusters. An accompanying video
is [here](https://youtu.be/avCPAJms3Fc). This demonstration uses 3 OpenShift 4 clusters. It is assumed that 3 OpenShift
clusters have already been deployed using of the deployment mechanisms defined at
https://cloud.openshift.com.

## Creating a Namespace and Deploying the Operator
The first step is to decide which of the clusters will run the Federation Operator.
Only one cluster runs the federation-controller-manager.

A new project of *pacman* is created within the OpenShift UI on cluster east1. Once the project
is created the next step is to deploy the operator.

Select OperatorHub</br>
![OperatorHub](../images/operatorhub.png)


Once the OperatorHub loads click Federation </br>
![Federation](../images/federation.png)

Once Federation has been chosen, information about the Operator will appear. It is
important to take note of the Operator Version as this will be needed when deciding
which version of Kubefedctl to use.

Select Install</br>
![Install Federation](../images/install.png)

Subscribe to the Federation Operator in the *pacman* namespace by clicking the
*Subscribe* button.
![Subscribe Federation](../images/subsribe.png)

Back at the command line run the following command looking for the status of Succeeded

NOTE: This may take a few minutes

## Kubeconfig
Specific items are required to be configured within the `kubeconfig` file before
federating clusters. By default the context is defined as *admin* in the `kubeconfig` file for OpenShift
4 clusters.  The directories below east-1, east-2, and west-2 represent the directories
containing independent OpenShift 4 clusters and the `kubconfig` relating to those OpenShift deployments.
Your cluster names may be different.
~~~sh
sed -i 's/admin/east1/g' east-1/auth/kubeconfig
sed -i 's/admin/east2/g' east-2/auth/kubeconfig
sed -i 's/admin/west2/g' west-2/auth/kubeconfig
export KUBECONFIG=`pwd`/east-1/auth/kubeconfig:`pwd`/east-2/auth/kubeconfig:`pwd`/west-2/auth/kubeconfig
oc config view --flatten > aws-east1-east2-west2
export KUBECONFIG=`pwd`/aws-east1-east2-west2
oc config set-context east1
~~~

## Install the `kubefedctl` binary

The `kubefedctl` tool manages federated cluster registration. Download the
v0.0.10 release and unpack it into a directory in your PATH (the
example uses `$HOME/bin`):

NOTE: The version may change as the operator matures. Verify that the version of
Federation matches the version of `kubefedctl`.

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

## Joining Clusters
Now that the `kubefedctl` binary has been acquired the next step is joining the clusters.
`kubefedctl` binary utilizes the contexts and clusters within `kubeconfig` when defining the clusters.

Using the `kubeconfig` file that was generated, verify the Operator has been successfully deployed.
~~~sh
$ oc get csv -n pacman
NAME                DISPLAY      VERSION   REPLACES   PHASE
federation.v0.0.10   Federation   0.0.10                Succeeded
~~~
The next step is to federate the clusters using `kubefedctl`.
~~~sh
kubefedctl join east1 --host-cluster-context east1 --add-to-registry --v=2 --federation-namespace=pacman
kubefedctl join east2 --host-cluster-context east1 --add-to-registry --v=2 --federation-namespace=pacman
kubefedctl join west2 --host-cluster-context east1 --add-to-registry --v=2 --federation-namespace=pacman

for type in namespaces deployments.apps ingresses.extensions secrets serviceaccounts services configmaps
do
  kubefedctl enable $type --federation-namespace pacman
done
~~~

Validate that the clusters are defined as `federatedclusters`.
~~~sh
oc get federatedclusters -n pacman
NAME    READY
east1   True
east2   True
west2   True
~~~

## Deploying *Pacman*
Now that the clusters are federated it is time to deploy the *pacman* application.
There are many different types of federated objects but they are somewhat similar to those
non-federated objects. For more information about federated objects see the following  [examples](https://github.com/kubernetes-sigs/kubefed/tree/master/example/sample1) and
the [user guide](https://github.com/kubernetes-sigs/kubefed/blob/master/docs/userguide.md).

For the *pacman* application, the first step is to modify the `pacman-federated-deployment-rs.yaml` file to reflect
the MongoDB endpoint. The MongoDB endpoint is used to save scores from the game.

Clone the demo code to your local machine:
~~~sh
git clone https://github.com/openshift/federation-dev.git
cd federation-dev/federated-pacman
~~~

Provide the value of the MongoDB server(s) to be used for the scores to be recorded
for the *pacman* game.
~~~sh
sed -i 's/replicamembershere/mongo-east1.apps.east-1.example1.com,mongo-east2.apps.east-2.example1.com,mongo-west2.apps.west-2.example1.com/g' 04-pacman-federated-deployment-rs.yaml
~~~

A value must be provided to be the publicly accessible address for the *pacman* application.
~~~sh
sed -i 's/pacmanhosthere/pacman.example1.com/g' 03-pacman-federated-ingress.yaml
~~~

Now deploy the *pacman* objects.
~~~sh
# Create the MongoDB secret
oc create -f 01-mongo-federated-secret.yaml
# Create the service
oc create -f 02-pacman-federated-service.yaml
# Create the ingress endpoint
oc create -f 03-pacman-federated-ingress.yaml
# Create the deployment
oc create -f 04-pacman-federated-deployment-rs.yaml
~~~

## Deploying HAProxy
Due to DNS TTLs, HAProxy is used to manage traffic of the *pacman* application
running on the different clusters. The use of HAProxy allows for faster failover
than TTLs can. This lowers the potential downtime when moving the *pacman* application
on and off of clusters.

A `configmap` will define the endpoints that were created when we created the ingress endpoint
using `03-pacman-federated-ingress.yaml`

A value must be provided to be the publicly accessible address for the *pacman* application. Also,
it is required to specify the cluster and the address of the *pacman* application which is routed by the OpenShift
router.
~~~sh
sed -i 's/pacmanhosthere/pacman.example1.com/g' 01-haproxy
sed -i 's/ROUTE1/west2 pacman.apps.west-2.example1.com:80/g' 01-haproxy
sed -i 's/ROUTE2/east2 pacman.apps.east-2.example1.com:80/g' 01-haproxy
sed -i 's/ROUTE3/east1 pacman.apps.east-1.example1.com:80/g' 01-haproxy
~~~

Create the `configmap` to be used by the HAProxy `deploymentconfig`.
~~~sh
oc create configmap haproxy --from-file=01-haproxy
~~~

A load balancer `service` is used to create a cloud provider load balancer. The Load balancer provides a publicly
available endpoint that can be used to assign a DNS A record.
~~~sh
# Create the HAProxy service
oc -n pacman create -f 02-haproxy-service.yaml
# Create the HAProxy deployment
oc -n pacman create -f 03-haproxy-deployment.yaml
~~~

## DNS
This demonstration uses Route53 for DNS. The first step is to look up the value of
the load balancer service and then assign a DNS A record.
~~~sh
oc -n pacman get svc haproxy-lb
NAME         TYPE           CLUSTER-IP       EXTERNAL-IP                                                               PORT(S)        AGE
haproxy-lb   LoadBalancer   172.31.161.224   ae294119d6d0d11e9b8b10e1ce99fb1b-1020848795.us-east-1.elb.amazonaws.com   80:31587/TCP   86m
~~~

The next step is to provide the load balancer `EXTERNAL-IP` to a the DNS zone to allow for routing.

NOTE: The A record will point to the publicly accessible address for the *pacman* application.

Enter the value of the publicly accessible address and use an Alias to point to the
`haproxy-lb` load balancer `ELB`.
![Route53](../images/route53.png)

## Play the Game
The game should be available now at the publicly accessible address. Make sure to
save the high score at the end of the game. This shows the data being persisted back to
the database.

## Moving the Application
By patching the `federateddeployment` the application can be scheduled and unscheduled between the clusters. The step below remove the *pacman* application from all clusters except for east2. This is done by modifying the `federateddeployment`
~~~sh
oc --context=east1 -n pacman patch federateddeployment pacman --type=merge -p '{"spec":{"overrides":[{"clusterName":"west2","clusterOverrides":[{"path":"spec.replicas","value":0}]},{"clusterName":"east1","clusterOverrides":[{"path":"spec.replicas","value":0}]}]}}'
~~~

The above command states that there should be 0 replicas in both east1 and west2. To verify
no pods are running in the other clusters the following command can be ran.

~~~sh
oc get deployment pacman --context east1 -n pacman
NAME     READY   UP-TO-DATE   AVAILABLE   AGE
pacman   0/0     0            0           132m

oc get deployment pacman --context east2 -n pacman
NAME     READY   UP-TO-DATE   AVAILABLE   AGE
pacman   1/1     1            1           132m


oc get deployment pacman --context west2 -n pacman
NAME     READY   UP-TO-DATE   AVAILABLE   AGE
pacman   0/0     0            0           132m
~~~

To populate the application back to all clusters use patch the `federateddeployment` again specifying 1 replica for all clusters.
~~~sh
oc --context=east1 -n pacman patch federateddeployment pacman --type=merge -p '{"spec":{"overrides":[{"clusterName":"west2","clusterOverrides":[{"path":"spec.replicas","value":1}]},{"clusterName":"east1","clusterOverrides":[{"path":"spec.replicas","value":1}]}]}}'
~~~

The most important thing to note during the modification of which clusters are running the
*pacman* application is that the scores persist regardless of which cluster the application is running and HAProxy always ensures the application is available.
