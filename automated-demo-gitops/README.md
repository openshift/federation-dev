# Automated Demo

This demo is intended to be used during OpenShift & GitOps presentations.

## Requirements

* oc tool installed on your local machine
* git and openssl commands available on your local machine
* 3 existing OCP 4.X/3.11 clusters and a user with admin access

## How-to

1. Edit the inventory file `inventory.json` (you can use the template `inventory.json.tmpl`)
2. The script will run the [scripted demo](./demo-script.md) in an automated way

The `inventory.json` files requires the following information:

* cluster1.url - Cluster1 domain name. e.g: east-1.example.com 
* cluster1.ocp_version - Cluster1 OCP Version. e.g: 3
* cluster1.admin_user - Cluster 1 admin user. e.g: admin
* cluster1.admin_password - Cluster 1 admin password. e.g: ver1secur3
* cluster2.url - Cluster2 domain name. e.g: east-2.example.com
* cluster2.ocp_version - Cluster2 OCP Version. e.g: 4
* cluster2.admin_user - Cluster 2 admin user. e.g: kubeadmin
* cluster2.admin_password - Cluster 2 admin password. e.g: ver1secur3
* cluster3.url - Cluster3 domain name. e.g: west-2.example.com
* cluster3.ocp_version - Cluster3 OCP Version. e.g: 4
* cluster3.admin_user - Cluster 3 admin user. e.g: kubeadmin
* cluster3.admin_password - Cluster 3 admin password. e.g: ver1secur3

## auto-demo options

The script has three execution modes: `demo` (default), `demo-cleanup` and `full-cleanup`.

  * The `demo` mode will go through all the required steps to run the demo from beggining to end
  * The `demo-cleanup` mode will delete the demo resources while preserving the Argo CD, Gogs and HAProxy bits
  * The `full-cleanup` mode will delete the demo resources and the Argo CD, Gogs and HAProxy bits

On top of that the script allows the user to select which steps will be executed.

  * By default all steps will be executed.
  * User can select one or more steps from the list:
    1. `context-creation` - Logs into the clusters and create the required contexts on oc tool
    2. `setup-argocd` - Setups Argo CD on Cluster 1
    3. `setup-gogs` - Setups Gogs on Cluster 1 and initializes an empty git repository
    4. `load-git-content` - Generates TLS certificates and modify some yaml resources accordingly, then pushes the files to the git repository on Gogs
    5. `demo-only` - Runs the demo we all love

The script has a help command integrated which will tell you the supported execution modes and steps:

```
./auto-demo.sh -h
```
