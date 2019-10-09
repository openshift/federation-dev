# GitOps Examples

In this directory are applications for use with Argo CD and Kustomize
to enable a GitOps workflow demonstrating our multicluster Pacman and MongoDB
deployments.


```
.
├── haproxy.txt                              # Example haproxy config file
└── pacman                                   # Pacman application
    ├── base                                 # Objects common to all clusters
    │   ├── kustomization.yaml               # Kustomize index pointing to files for base
    │   ├── mongodb-users-secret.yaml        # ConfigMap for logging into Mongo DB
    │   ├── namespace.yaml                   # Creates the skuppman ns
    │   ├── pacman-deployment.yaml           # Deploys the pacman app
    │   ├── pacman-serviceaccount.yaml
    │   ├── pacman-service.yaml
    │   ├── skuppman-clusterrolebinding.yaml
    │   ├── skuppman-clusterrole.yaml
    │   └── skuppman-route.yaml
    └── overlays                             # Overlay directories for cluster specific differences
        └── east1                            # Our example first cluster in US East-1 region
            ├── haproxy-configmap.yaml       # HAProxy configuration as ConfigMap
            ├── haproxy-deployment.yaml      # HAProxy deployment to ingress all three clusters
            ├── haproxy-service.yaml
            └── kustomization.yaml           # Kustomize index for east1 overlays
```
