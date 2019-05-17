# Automated Demo

This demo is intended to be used during Kubefed presentations.

## Requirements

* oc tool installed on your local machine
* git and openssl commands available on your local machine
* 3 existing OCP 4.1 clusters and a user with admin access
* An existing DNS record for the pacman load balancer
* A pacman loadbalancer deployed and loadbalancing traffic across the three different clusters [1]

## How-to

1. Edit the inventory file `inventory.json` (you can use the template `inventory.json.tmpl`) or input the requested data interactively
2. The script will run the [scripted demo](./demo-script.md) in an automated way

The `inventory.json` files requires the following information:

* cluster1.url - Cluster1 domain name. e.g: east-1.example.com 
* cluster2.url - Cluster2 domain name. e.g: east-2.example.com
* cluster3.url - Cluster3 domain name. e.g: west-2.example.com
* pacman_lb_url - The DNS record configured to point to our Pacman Load Balancer. e.g: pacman.example.com
* admin_user - Username which can connect to all clusters using the passwords defined in the cluster sections

## auto-demo options

The script has three execution modes: `demo` (default), `demo-cleanup` and `full-cleanup`.

  * The `demo` mode will go through all the required steps to run the demo from beggining to end
  * The `demo-cleanup` mode will delete the demo resources while preserving the kubefed bits
  * The `full-cleanup` mode will delete the demo resources and the federation bits (including the namespace where it was deployed)

On top of that the script allows the user to select which steps will be executed.

  * By default all steps will be executed.
  * User can select one or more steps from the list:
    1. `context-creation` - Logs into the clusters and create the required contexts on oc tool
    2. `setup-kubefed` - Setups Kubefed on the contexts created before
    3. `setup-mongo-tls` - Generates TLS certificates and modify some yaml resources accordingly
    4. `demo-only` - Runs the demo we all love

The script has a help command integrated which will tell you the supported execution modes and steps:

```
./auto-demo.sh -h
```

[1] For information about configuring HaProxy visit [this readme](./deploy-haproxy.md)
