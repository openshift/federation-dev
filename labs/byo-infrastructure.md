<a id="markdown-bring-your-own-infrastructure" name="bring-your-own-infrastructure"></a>

# BYO Infrastructure

This lab is prepared for the Red Hat Tech Exchange 2019 event.

For this lab users are presented with pre-existing infrastructure as well as some automation mechanisms.

This document aims to define all the required steps needed to be able to follow this lab outside of the RHTE event.

## Clusters Deployment

This Lab requires at least three [OpenShift Container Platform](https://www.openshift.com/) 4.1 clusters.

The clusters can be deployed using the [developer preview on AWS](https://cloud.redhat.com/openshift/install)

## Tooling Download

The following tools are used during the labs and must be present in the system used by the student to interact with the clusters.

* argocd
    
    ```sh
    curl -LOs https://github.com/argoproj/argo-cd/releases/download/v1.0.2/argocd-linux-amd64
    mv argocd-linux-amd64 /usr/local/bin/argocd
    chmod +x /usr/local/bin/argocd
    ```
* cfssl

    ```sh
    curl -LOs https://pkg.cfssl.org/R1.2/cfssl_linux-amd64
    mv cfssl_linux-amd64 /usr/local/bin/cfssl
    chmod +x /usr/local/bin/cfssl
    ```
* cfssljson

    ```sh
    curl -LOs https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64
    mv cfssljson_linux-amd64 /usr/local/bin/cfssljson
    chmod +x /usr/local/bin/cfssljson
    ```

## Deploy ArgoCD

Argo CD Server needs to be deployed to the first cluster.

Steps to deploy Argo CD can be found in [this AgnosticD role](https://github.com/redhat-cop/agnosticd/tree/development/ansible/roles/ocp4-workload-rhte-kubefed-app-portability)

## Deploy Gogs Server

Gogs Git Server needs to be deployed to the first cluster.

Steps to deploy Gogs can be found in [this AgnosticD role](https://github.com/redhat-cop/agnosticd/tree/development/ansible/roles/ocp4-workload-rhte-kubefed-app-portability)

## Helper Scripts

Helper Scripts should be deployed under `/usr/local/bin` on the Client VM used by the Student to run the lab.

The Helper Scripts can be found [here](./utility/)