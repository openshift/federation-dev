# Red Hat Tech Exchange Lab - Hands on with Red Hat Multi-Cluster Federation: Application Portability

This page contains a series of labs to be conducted during Red Hat Tech exchange.

During the labs you will be deploying some federated workloads on three OpenShift 4 clusters that have been pre-deployed for you.

If during the labs you need to start over check out the [cleanup instructions](./cleanup-instructions.md)

You will be using some helper scripts during the labs, below a reference table:

| Helper Script             | Description                                                                                            | When should I use it?                        |
|---------------------------|--------------------------------------------------------------------------------------------------------|----------------------------------------------|
| init-lab                  | Backups the current lab folder and download the lab again so student can start over                    | Only if requested by the instructor          |
| gen-mongo-certs           | Generates the required certificates for MongoDB on Lab5                                                | Only if requested by the instructor          |
| namespace-cleanup         | Deletes everything inside the namespace sent as parameter and the namespace itself from all clusters   | Only if you need to start a lab from scratch |
| wait-for-deployment       | Waits until a given deployment in a given cluster and namespace is ready (all replicas up and running) | When required by instructions                |
| wait-for-mongo-replicaset | Waits until the MongoDB ReplicaSet is configured in a given cluster and namespace                      | When required by instructions                |

In order to get started with the lab, click on **Lab 0 - Introduction**.

## Labs Index

* [Lab 0 - Introduction](./intro.md)<br>
* [Lab 1 - Prerequisites](./1.md)<br>
* [Lab 2 - Login into OpenShift Clusters and Configure Context](./2.md)<br>
* [Lab 3 - Deploy Federation](./3.md)<br>
* [Lab 4 - Deploying and Managing a Project with GitOps](./4.md)<br>
* [Lab 5 - Deploying MongoDB](./5.md)<br>
* [Lab 6 - Deploying Pacman](./6.md)<br>
* [Lab 7 - Application Portability](./7.md)<br>
* [Lab 8 - Convert a Namespace to a Federated Namespace](./8.md)<br>
* [Lab 9 - Disaster Recovery](./10.md)<br>
* [Lab 10 - Wrap up](./11.md)<br>
