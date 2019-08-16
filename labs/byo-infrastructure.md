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

* kubefedctl
    
    ```sh
    curl -LOs https://github.com/kubernetes-sigs/kubefed/releases/download/v0.1.0-rc4/kubefedctl-0.1.0-rc4-linux-amd64.tgz
    tar xzf kubefedctl-0.1.0-rc4-linux-amd64.tgz -C /usr/local/bin/
    chmod +x /usr/local/bin/kubefedctl
    rm -f kubefedctl.tgz
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

## Deploy KubeFed Operator

KubeFed Operator will be deployed to the first cluster, the following steps must be run **only** in one of the clusters as cluster admin.

1. Create the `kube-federation-system` namespace
    
    ```sh
    oc create ns kube-federation-system
    ```
2. Create the `CatalogSourceConfig`

    ```sh
    cat <<-EOF | oc apply -f -
    ---
    apiVersion: operators.coreos.com/v1
    kind: CatalogSourceConfig
    metadata:
      name: installed-kubefed-kube-federation-system
      namespace: openshift-marketplace
    spec:
      csDisplayName: Community Operators
      csPublisher: Community
      targetNamespace: kube-federation-system
      packages: kubefed-operator
    ---
    EOF
    ```
3. Create the `OperatorGroup`

    ```sh
    cat <<-EOF | oc apply -n kube-federation-system -f -
    ---
    apiVersion: operators.coreos.com/v1
    kind: OperatorGroup
    metadata:
      name: kubefed
    spec:
      targetNamespaces:
      - kube-federation-system
    ---
    EOF
    ```
4. Create the `Subscription`

    ```sh
    cat <<-EOF | oc apply -n kube-federation-system -f -
    ---
    apiVersion: operators.coreos.com/v1alpha1
    kind: Subscription
    metadata:
      name: federation
    spec:
      channel: alpha
      installPlanApproval: Manual
      name: kubefed-operator
      package: kubefed-operator
      startingCSV: kubefed-operator.v0.1.0
      source: installed-kubefed-kube-federation-system
      sourceNamespace: kube-federation-system
    ---
    EOF
    ```
5. Approve the `InstallPlan` (It may take some time to be created)

    ```sh
    oc -n kube-federation-system get installplan
    oc -n kube-federation-system patch installplan <installplan_name> --type merge -p '{"spec":{"approved":true}}'
    ```
6. Wait `ClusterServiceVersion` to succeed (it may take some time to Succeed)

    ```sh
    oc -n kube-federation-system get csv
    ```