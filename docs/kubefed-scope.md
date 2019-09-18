# KubeFed Cluster-Scoped VS Namespace-Scoped

## Cluster Scoped
### What distinguishes cluster-scoped KubeFed?
* A key factor is the ability to federate non-namespaced k8s objects.
* Cluster joins will count for multiple namespaces rather than maintaining cluster connection info per namespace.
* Controllers will watch for FederatedNamespaces in all namespaces.
* Cluster-scoped KubeFed requires cluster-admin level access in member clusters.

### How is the installation different for cluster-scoped KubeFed?
* We recommend to install the KubeFed Operator in single namespace mode, and use “kube-federation-system” as the namespace to watch as this is the default for the kubefedctl tool.
* If using the KubeFed Operator, create KubeFedWebHook and KubeFed Custom Resources in the chosen namespace, setting the “spec | scope” of the latter resource to “Cluster”.
* Join cluster(s). If KubeFed is installed in the “kube-federation-system” namespace, there is no need to specify --kubefed-namespace parameter.
* If necessary, enable additional resource types to federate, remembering that any namespaced resource types will also require that the “Namespaces” resource type itself be enabled. You can see a list of existing enabled types by using kubectl or oc to “get” federatedtypeconfigs from the kubefed namespace.
* Federate any namespaces containing federated resources intended for propagation. 

### Are non-namespaced types’ federated templates themselves namespaced?
* No, non-namespaced resource types are templated by non-namespaced federated types.
* Namespaces are the exception where FederatedNamespaces are themselves namespaced

## Namespace Scoped

### What distinguishes a namespace-scoped KubeFed?
* The namespace-scoped KubeFed controller only watches for federated types within its own namespace.
* As non-namespaced resources are not contained in a namespace, they are not able to be propagated by namespace scoped KubeFed.
* The configuration of KubeFed also belongs in its namespace, including FederatedTypeConfig resources and KubeFedCluster resources (tracking joined clusters). This means that KubeFed controllers on the same cluster in different namespaces could enable a different set of types, and join a different set of clusters.

### How is the installation and setup different for namespaced KubeFed?
* The KubeFed Operator should be deployed to watch all namespaces--the default behavior. 
* Deploy one controller-manager per namespace by creating a namespaced KubeFed CR (“spec | scope” is “Namespaced”)
* All subsequent kubefedctl commands should specify their namespace with the “--kubefed-namespace” parameter.
* Enable “Namespaces” (it is not necessary to federate the namespace, that happens implicitly) and any other desired types per Namespace.
* Join member clusters per Namespace.

## Comparing both

### When do you want to use cluster scoped?
* When you have resources to federate which are not namespaced.  A good example is a federated ClusterRoleBinding.
* If you want to federate multiple namespaces, a cluster-scoped KubeFed allows them to work with one control plane, and one set of cluster relationships rather than establishing connections per namespace.

### When might you want to use namespaced-scoped KubeFed?
* When you have multiple tenants in a cluster and you only want a subset of them to be capable of working in a federated role.
* To limit the scope of kubefed access to member clusters (admin in a namespace vs cluster-admin)
* Creating multiple control planes effectively creates multiple failure domains (the failure of one control plane does not cause all resource federation to stop)

### Can you use both scopes together?
* Cluster and namespaced control planes should not be deployed to the same host cluster concurrently. Either a) one cluster-scoped control plane or b) one or more namespace-scoped control planes

### Can you switch from namespace-scoped to cluster-scoped?
* Joining a cluster involves the creation of a service account in the joining cluster with scope-appropriate privileges. Accordingly, switching the scope of a control plane requires updating the service account for member clusters to have permissions for the new scope. This could be accomplished as follows:
  * scale down the kubefed control plane
  * update the KubeFedConfig named 'kubefed' in the system namespace to use the new scope (this requires deleting and recreating since the scope is immutable in the config)
  * unjoin all member clusters
  * join all member clusters (taking care to use the same names they were previously joined with to ensure placement consistency)
* Namespaced federated resources would not require any modification if the scope of their managing control plane changed and the names of clusters were maintained across unjoining and rejoining.

### In cluster-scoped, which namespaces, exactly, get propagated across clusters?
* Only the namespaces for which there exists a FederatedNamespace (itself in the namespace)

### Which namespaces are protected/forbidden from federation?
* All namespaces can contain federated resources. KubeFed explicitly avoids attempting to create, update, or delete the following namespaces in member clusters:
  * kube-system
  * kube-public
  * default
  * kubefed system namespace

## Notes

In general, the concept of namespacing is a k8s primitive. Not something KubeFed specific. You can check by looking at the API resources and determine what is namespace scoped vs. cluster scoped.
