# GitOps Examples

In this directory are applications for use with Argo CD and Kustomize
to enable a GitOps workflow demonstrating our multicluster Pacman and MongoDB
deployments.

To use the structure, you would create three Argo CD application with arguments similar to:

    argocd app create --project default \
    --name skuppman-east1 \
    --repo https://github.com/openshift/federation-dev \
    --dest-namespace skuppman \
    --revision master \
    --sync-policy none \
    --path gitops/pacman/overlays/east1 \
    --dest-server https://kubernetes.default.svc

    argocd app create --project default \
    --name skuppman-east2 \
    --repo https://github.com/openshift/federation-dev \
    --dest-namespace skuppman \
    --revision master \
    --sync-policy none \
    --path gitops/pacman/base \
    --dest-server https://api.east-2.example.com:6443

    argocd app create --project default \
    --name skuppman-west2 \
    --repo https://github.com/openshift/federation-dev \
    --dest-namespace skuppman \
    --revision master \
    --sync-policy none \
    --path gitops/pacman/base \
    --dest-server https://api.west-2.example.com:6443

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
