# Modifying Federated Deployments with Tekton Pipelines
Tekton pipelines are a new exciting way to build and deploy resources. Tekton works by spinning up temporary containers to do [tasks](./modify-federated-deployment-task.yaml) such a build an image using s2i or deploy a resource. A series of tasks can be grouped together into a *pipeline*. A pipeline is a collection of tasks to be ran in a specific order.

## Updating Pacman
As we saw with previous demonstartions *pacman* is a fun simple application to deploy across multiple OpenShift clusters but what if we want to update the application?

The following demonstration will build a new *pacman* image and patch the current deployment of *pacman* to use the newest image.

### Requirements
* A repository accessible by all clusters
* Tekton deployed on the cluster running the 
