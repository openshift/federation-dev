<a id="markdown-clean-up-4" name="clean-up-4"></a>

You will be using some helper scripts during the labs, below a reference table:

| Helper Script             | Description                                                                                            | When should I use it?                        |
|---------------------------|--------------------------------------------------------------------------------------------------------|----------------------------------------------|
| init-lab                  | Backups the current lab folder and download the lab again so student can start over                    | Only if requested by the instructor          |
| gen-mongo-certs           | Generates the required certificates for MongoDB on Lab5                                                | Only if requested by the instructor          |
| namespace-cleanup         | Deletes everything inside the namespace sent as parameter and the namespace itself from all clusters   | Only if you need to start a lab from scratch |
| wait-for-deployment       | Waits until a given deployment in a given cluster and namespace is ready (all replicas up and running) | When required by instructions                |
| wait-for-mongo-replicaset | Waits until the MongoDB ReplicaSet is configured in a given cluster and namespace                      | When required by instructions                |
| wait-for-argo-app         | Waits until a give Argo application is reported as healthy                                             | When required by instructions                |
| argocd-add-clusters       | Adds all clusters to Argo CD using a workaround to avoid colliding secrets error                       | When required by instructions                |
| verify-contexts           | Verifies contexts cluster1, cluster2 and cluster3 are created and they work as expected                | When required by instructions                |

# Lab 4 Clean up
To clean up the test application run:

~~~sh
argocd app delete rhte-simple-app
~~~

<a id="markdown-clean-up-6" name="clean-up-6"></a>

# Lab 6 Clean Up
To clean up the MongoDB Application run:

~~~sh
argocd app delete cluster1-mongo
argocd app delete cluster2-mongo
argocd app delete cluster3-mongo
~~~

<a id="markdown-clean-up-7" name="clean-up-7"></a>

# Lab 7 Clean Up
To clean up the HAProxy LB and Pacman Application run:

~~~sh
namespace-cleanup -n haproxy-lb
argocd app delete cluster1-pacman
argocd app delete cluster2-pacman
argocd app delete cluster3-pacman
~~~
