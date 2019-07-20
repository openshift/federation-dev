#!/bin/bash

# GLOBAL VAR
KUBEFED_RELEASE="v0.1.0-rc3"
CSV_RELEASE="v0.1.0"

usage()
{
  echo "$0 [-m|--mode MODE] [-s|--steps STEPS]"
  echo -ne "\noptions:\n"
  echo "-m|--mode - Accepted values: [demo|full-cleanup|demo-cleanup]." 
  echo "  Demo will perform the demo, demo-cleanup will delete mongo and pacman resources plus kubefed operator"
  echo "  full-cleanup will delete everything including the namespace where the demo was deployed. Default value: demo"
  echo "-s|--steps - Accepted values: [context-creation|setup-kubefed|setup-mongo-tls|demo-only]."
  echo "  Any combination of these sepparated by commas will run only those steps. Default value: all"
  echo "-n|--namespace - Accepted values: name of the namespace where the demo will be deployed. Default value: federation-demo"
  echo "  e.g: my-pacman-demo"
  echo "--ci-mode"
  echo "  The script will run in CI mode, which means no user interaction is needed"
  echo -ne "\nexamples:\n"
  echo "run everything (default): $0"
  echo "cleanup demo resources: $0 -m demo-cleanup"
  echo "run only the demo steps: $0 -s demo-only"
  echo "run context creation and demo: $0 -s demo-only,context-creation"
}

check_tools()
{
   git version &> /dev/null
   if [ $? -ne 0 ]; then
     echo "Git not available, exiting..." 
     exit 1
   fi
   # oc version fails if unable to connect to server
   oc help &> /dev/null
   if [ $? -ne 0 ]; then
     echo "oc tool not available, exiting..."
     exit 1
   fi
   openssl version &> /dev/null
   if [ $? -ne 0 ]; then
     echo "openssl not available, exiting..."
     exit 1
   fi
}

run_ok_or_fail()
{
  SHOW_OUTPUT=$2
  RETRY=$3
  NO_EXIT=$4
  echo -ne "Executing command: "
  echo -e "\e[33m\e[1m$1 \e[21m\e[0m"
  if [ "0$SHOW_OUTPUT" -eq "01" ]
  then
    echo ""
    eval "$1"
    echo ""
  else
    eval "$1" &> /dev/null
  fi
  if [ $? -ne 0 ]
  then
    if [ "0$RETRY" -eq "01" ]
    then
      echo "Command failed... retrying in 5 seconds"
      sleep 5
      run_ok_or_fail "$1" "$SHOW_OUTPUT" "0" "$NO_EXIT"
    else
      if [ "0$NO_EXIT" -eq "01" ]
      then
        echo "Command failed... continuing"
        return
      else
        echo "Command failed... exiting"
        exit 1
      fi
    fi
  else
    echo "Command succeeded."
  fi
}

context_creation()
{
  CONTEXT_NAME=$1
  API_URL=$2
  ADMIN_USER=$3
  ADMIN_PWD=$4
  echo "Deleting and re-creating context ${CONTEXT_NAME}"
  oc config delete-context ${CONTEXT_NAME} &> /dev/null
  oc login ${API_URL} --username=${ADMIN_USER} --password=${ADMIN_PWD} --insecure-skip-tls-verify=true &> /dev/null
  if [ $? -ne 0 ]; then
    echo "Login failed for ${API_URL}... exiting"
    exit 1
  fi
  run_ok_or_fail "oc config rename-context $(oc config current-context) ${CONTEXT_NAME}" "0" "0"
}

get_data_from_user()
{
  echo "Input data examples:"
  echo "  Cluster1 URL: east-1.example.com"
  echo "  Pacman LB URL: pacman.example.com"
  echo "  OCP Admin User: kubeadmin"
  echo "  Cluster1 Admin password: kN7Ts-V3Ry-S3cur3-8SfD8"
  echo "--------------------"
  read -rp "Cluster1 URL: " CLUSTER1_URL
  read -rp "Cluster1 OCP Version [3|4]: " CLUSTER1_VERSION
  read -rp "Cluster2 URL: " CLUSTER2_URL
  read -rp "Cluster2 OCP Version [3|4]: " CLUSTER2_VERSION
  read -rp "Cluster3 URL: " CLUSTER3_URL 
  read -rp "Cluster3 OCP Version [3|4]: " CLUSTER3_VERSION
  read -rp "Pacman LB URL: " PACMAN_URL
  read -rp "OCP Admin User: " ADMIN_USER
  read -rp "Cluster1 Admin: " CLUSTER1_ADMIN
  read -rp "Cluster1 Admin Password: " CLUSTER1_ADMIN_PWD
  read -rp "Cluster2 Admin: " CLUSTER2_ADMIN
  read -rp "Cluster2 Admin Password: " CLUSTER2_ADMIN_PWD
  read -rp "Cluster3 Admin: " CLUSTER3_ADMIN
  read -rp "Cluster3 Admin Password: " CLUSTER3_ADMIN_PWD
  CLUSTER1_API_URL="https://api.${CLUSTER1_URL}:6443"
  CLUSTER2_API_URL="https://api.${CLUSTER2_URL}:6443"
  CLUSTER3_API_URL="https://api.${CLUSTER3_URL}:6443"
  if [ "0$CLUSTER1_VERSION" == "03" ]
  then
    CLUSTER1_API_URL="https://console.${CLUSTER1_URL}:8443"
  fi
  if [ "0$CLUSTER2_VERSION" == "03" ]
  then
    CLUSTER2_API_URL="https://console.${CLUSTER2_URL}:8443"
  fi
  if [ "0$CLUSTER3_VERSION" == "03" ]
  then
    CLUSTER3_API_URL="https://console.${CLUSTER3_URL}:8443"
  fi
  echo "--------------------"
  echo "Input data"
  echo "Cluster 1 Domain: ${CLUSTER1_URL} - API: ${CLUSTER1_API_URL} - Admin User: ${CLUSTER1_ADMIN}"
  echo "Cluster 2 Domain: ${CLUSTER2_URL} - API: ${CLUSTER2_API_URL} - Admin User: ${CLUSTER2_ADMIN}"
  echo "Cluster 3 Domain: ${CLUSTER3_URL} - API: ${CLUSTER3_API_URL} - Admin User: ${CLUSTER3_ADMIN}"
  echo "Pacman LB URL: ${PACMAN_URL}"
}

get_data_from_inventory()
{
  INVENTORY=$1
  download_jq_binary
  CLUSTER1_URL=$(./bin/jq -r '.cluster1.url' $INVENTORY)
  CLUSTER1_VERSION=$(./bin/jq -r '.cluster1.ocp_version' $INVENTORY)
  CLUSTER2_URL=$(./bin/jq -r '.cluster2.url' $INVENTORY)
  CLUSTER2_VERSION=$(./bin/jq -r '.cluster2.ocp_version' $INVENTORY)
  CLUSTER3_URL=$(./bin/jq -r '.cluster3.url' $INVENTORY)
  CLUSTER3_VERSION=$(./bin/jq -r '.cluster3.ocp_version' $INVENTORY)
  CLUSTER1_API_URL="https://api.${CLUSTER1_URL}:6443"
  CLUSTER2_API_URL="https://api.${CLUSTER2_URL}:6443"
  CLUSTER3_API_URL="https://api.${CLUSTER3_URL}:6443"
  if [ "0$CLUSTER1_VERSION" == "03" ]
  then
    CLUSTER1_API_URL="https://console.${CLUSTER1_URL}:8443"
  fi
  if [ "0$CLUSTER2_VERSION" == "03" ]
  then
    CLUSTER2_API_URL="https://console.${CLUSTER2_URL}:8443"
  fi
  if [ "0$CLUSTER3_VERSION" == "03" ]
  then
    CLUSTER3_API_URL="https://console.${CLUSTER3_URL}:8443"
  fi
  PACMAN_URL=$(./bin/jq -r '.pacman_lb_url' $INVENTORY)
  ADMIN_USER=$(./bin/jq -r '.admin_user' $INVENTORY)
  CLUSTER1_ADMIN=$(./bin/jq -r '.cluster1.admin_user' $INVENTORY)
  CLUSTER1_ADMIN_PWD=$(./bin/jq -r '.cluster1.admin_password' $INVENTORY)
  CLUSTER2_ADMIN=$(./bin/jq -r '.cluster2.admin_user' $INVENTORY)
  CLUSTER2_ADMIN_PWD=$(./bin/jq -r '.cluster2.admin_password' $INVENTORY)
  CLUSTER3_ADMIN=$(./bin/jq -r '.cluster3.admin_user' $INVENTORY)
  CLUSTER3_ADMIN_PWD=$(./bin/jq -r '.cluster3.admin_password' $INVENTORY)
  echo "Data gathered from inventory: $INVENTORY" 
  echo "Cluster 1 Domain: ${CLUSTER1_URL} - API: ${CLUSTER1_API_URL} - Admin User: ${CLUSTER1_ADMIN}"
  echo "Cluster 2 Domain: ${CLUSTER2_URL} - API: ${CLUSTER2_API_URL} - Admin User: ${CLUSTER2_ADMIN}"
  echo "Cluster 3 Domain: ${CLUSTER3_URL} - API: ${CLUSTER3_API_URL} - Admin User: ${CLUSTER3_ADMIN}"
  echo "Pacman URL: $PACMAN_URL"
}

get_input_data()
{
  INVENTORY_FILE="./inventory.json"
  if [ -s ${INVENTORY_FILE} ]
  then
    get_data_from_inventory ${INVENTORY_FILE}
  else
    get_data_from_user
  fi
}

check_federated_clusters_ready()
{
  READY=0
  WAIT=0
  MAX_WAIT=300
  echo "Checking if Federated Clusters are ready"
  FEDERATED_CLUSTERS_STATE_READY=$(oc --context=feddemocl1 describe kubefedclusters -n kube-federation-system | grep -c ClusterReady)
  DESIRED_READY_CLUSTERS=3
  while [ $READY -eq 0 ]
  do
    FEDERATED_CLUSTERS_STATE_READY=$(oc --context=feddemocl1 describe kubefedclusters -n kube-federation-system | grep -c ClusterReady)
    if [ "0$FEDERATED_CLUSTERS_STATE_READY" -eq "0$DESIRED_READY_CLUSTERS" ]
    then
      echo "Federated Clusters are ready"
      READY=1
    else
      echo "Federated Clusters are not ready yet, waiting... [$WAIT/$MAX_WAIT]"
      sleep 5
      WAIT=$(expr $WAIT + 5)
    fi
    if [ $WAIT -ge $MAX_WAIT ]
    then
      echo "Timeout while waiting Federated Clusters to become ready"
      exit 1
    fi
  done
}

download_jq_binary()
{
  if [ ! -s "bin/jq" ]
  then
    echo "Downloading jq tool binary"
    run_ok_or_fail "curl -Ls https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 -o bin/jq && chmod +x bin/jq" "0" "1"
  fi
}

download_kubefed_binary()
{
  if [ ! -s "bin/kubefedctl" ]
  then
    echo "Downloading kubefedctl binary"
    KUBEFED_BIN_RELEASE=$(echo $KUBEFED_RELEASE | sed "s/v//g")
    run_ok_or_fail "curl -Ls https://github.com/kubernetes-sigs/kubefed/releases/download/${KUBEFED_RELEASE}/kubefedctl-${KUBEFED_BIN_RELEASE}-linux-amd64.tgz -o - | tar xvz -C ./bin/" "0" "1"
  fi
}

setup_kubefed()
{
  download_kubefed_binary
  echo "Creating namespace ${DEMO_NAMESPACE} for deploying the demo"
  run_ok_or_fail "oc --context=feddemocl1 create ns kube-federation-system" "0" "1"
  run_ok_or_fail "oc --context=feddemocl1 create ns ${DEMO_NAMESPACE}" "0" "1"
  echo "Deploying Federation Operator on Host Cluster in namespace ${DEMO_NAMESPACE}"
  # Here detect if feddemocl1 is 3.11 or 4.X
  
  HOST_CLUSTER_VERSION=$(oc --context=feddemocl1 get clusterversion version -o jsonpath='{.spec.channel}' || echo "3") 
  if [ ${HOST_CLUSTER_VERSION} == "3" ]
  then
    echo "Deploying OLM"
    cp -pf yaml-resources/olm/01-olm.yaml yaml-resources/olm/01-olm-mod.yaml &> /dev/null
    cp -pf yaml-resources/olm/02-olm.yaml yaml-resources/olm/02-olm-mod.yaml &> /dev/null
    cp -pf yaml-resources/olm/03-subscription.yaml yaml-resources/olm/03-subscription-mod.yaml &> /dev/null
    run_ok_or_fail "oc --context=feddemocl1 apply -f yaml-resources/olm/01-olm-mod.yaml" "0" "1"
    run_ok_or_fail "oc --context=feddemocl1 apply -f yaml-resources/olm/02-olm-mod.yaml" "0" "1"
    wait_for_deployment_ready "feddemocl1" "olm" "olm-operator"
    wait_for_deployment_ready "feddemocl1" "olm" "catalog-operator"
    echo "Configuring CatalogSourceConfig and Subscription with demo data"
    run_ok_or_fail "oc --context=feddemocl1 -n kube-federation-system create -f yaml-resources/olm/03-subscription-mod.yaml" "0" "1"
  else
    echo "Configuring CatalogSourceConfig and Subscription with demo data"
    cp -pf yaml-resources/kubefed-operator/01-catalog-source-config.yaml yaml-resources/kubefed-operator/01-catalog-source-config-mod.yaml &> /dev/null
    cp -pf yaml-resources/kubefed-operator/02-federation-operator-group.yaml yaml-resources/kubefed-operator/02-federation-operator-group-mod.yaml &> /dev/null
    cp -pf yaml-resources/kubefed-operator/03-federation-subscription.yaml yaml-resources/kubefed-operator/03-federation-subscription-mod.yaml &> /dev/null
    run_ok_or_fail "oc --context=feddemocl1 -n openshift-marketplace create -f yaml-resources/kubefed-operator/01-catalog-source-config-mod.yaml" "0" "1"
    run_ok_or_fail "oc --context=feddemocl1 -n kube-federation-system create -f yaml-resources/kubefed-operator/02-federation-operator-group-mod.yaml" "0" "1"
    run_ok_or_fail "oc --context=feddemocl1 -n kube-federation-system create -f yaml-resources/kubefed-operator/03-federation-subscription-mod.yaml" "0" "1"
  fi
  wait_for_csv_completed "feddemocl1" "kube-federation-system" "kubefed-operator.${CSV_RELEASE}"
  run_ok_or_fail "oc --context=feddemocl1 -n kube-federation-system create -f yaml-resources/kubefed-operator/04-kubefed-resource.yaml"
  wait_for_deployment_ready "feddemocl1" "kube-federation-system" "kubefed-controller-manager"
  echo "Enabling federated resources on Host Cluster (may take a while)"
  for type in namespaces ingresses.extensions secrets serviceaccounts services configmaps persistentvolumeclaims deployments.apps roles.rbac.authorization.k8s.io rolebindings.rbac.authorization.k8s.io clusterrolebindings.rbac.authorization.k8s.io clusterroles.rbac.authorization.k8s.io
  do
    run_ok_or_fail "./bin/kubefedctl enable "${type}" --host-cluster-context feddemocl1" "0" "1"
  done
  echo "Joining Cluster1 to ClusterRegistry"
  run_ok_or_fail "./bin/kubefedctl join feddemocl1 --host-cluster-context feddemocl1 --v=2" "0" "1"
  echo "Joining Cluster2 to ClusterRegistry"
  run_ok_or_fail "./bin/kubefedctl join feddemocl2 --host-cluster-context feddemocl1 --v=2" "0" "1"
  echo "Joining Cluster3 to ClusterRegistry"
  run_ok_or_fail "./bin/kubefedctl join feddemocl3 --host-cluster-context feddemocl1 --v=2" "0" "1"
  check_federated_clusters_ready
  run_ok_or_fail "oc --context=feddemocl1 -n kube-federation-system get kubefedclusters" "1" "1"
  run_ok_or_fail "kubefedctl federate namespace ${DEMO_NAMESPACE} --host-cluster-context feddemocl1" "1" "1"
  echo "feddemocl1 - ${CLUSTER1_URL}"
  echo "feddemocl2 - ${CLUSTER2_URL}"
  echo "feddemocl3 - ${CLUSTER3_URL}"
  echo "Federation setup completed"
}

setup_mongo_tls()
{
  SERVICE_NAME=mongo
  NAMESPACE=${DEMO_NAMESPACE}
  ROUTE_CLUSTER1="mongo-${DEMO_NAMESPACE}.apps.${CLUSTER1_URL}"
  ROUTE_CLUSTER2="mongo-${DEMO_NAMESPACE}.apps.${CLUSTER2_URL}"
  ROUTE_CLUSTER3="mongo-${DEMO_NAMESPACE}.apps.${CLUSTER3_URL}"
  SANS="localhost,localhost.localdomain,127.0.0.1,${ROUTE_CLUSTER1},${ROUTE_CLUSTER2},${ROUTE_CLUSTER3},${SERVICE_NAME},${SERVICE_NAME}.${NAMESPACE},${SERVICE_NAME}.${NAMESPACE}.svc.cluster.local"
  cd ssl &> /dev/null
  echo "Downloading cfssl binary"
  run_ok_or_fail "curl -Ls https://pkg.cfssl.org/R1.2/cfssl_linux-amd64 -o ../bin/cfssl && chmod +x ../bin/cfssl" "0" "1"
  echo "Downloading cfssljson binary"
  run_ok_or_fail "curl -Ls https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64 -o ../bin/cfssljson && chmod +x ../bin/cfssljson" "0" "1"
  echo "Generating CA"
  run_ok_or_fail "../bin/cfssl gencert -initca ca-csr.json | ../bin/cfssljson -bare ca" "0" "1"
  echo "Generating MongoDB Certs"
  run_ok_or_fail "../bin/cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -hostname=${SANS} -profile=kubernetes mongodb-csr.json | ../bin/cfssljson -bare mongodb" "0" "1"
  echo "Generating a PEM with MongoDB Cert Priv/Pub Key"
  cat mongodb-key.pem mongodb.pem > mongo.pem 
  echo "Crafting MongoDB OCP Secret containing certificates information"
  cp -pf ../yaml-resources/mongo/01-mongo-federated-secret.yaml ../yaml-resources/mongo/01-mongo-federated-secret-mod.yaml &> /dev/null
  cp -pf ../yaml-resources/mongo/04-mongo-federated-deployment-rs.yaml ../yaml-resources/mongo/04-mongo-federated-deployment-rs-mod.yaml &> /dev/null
  cp -pf ../yaml-resources/pacman/03-pacman-federated-ingress.yaml ../yaml-resources/pacman/03-pacman-federated-ingress-mod.yaml &> /dev/null
  cp -pf ../yaml-resources/pacman/07-pacman-federated-deployment-rs.yaml ../yaml-resources/pacman/07-pacman-federated-deployment-rs-mod.yaml &> /dev/null
  run_ok_or_fail 'sed -i "s/mongodb.pem: .*$/mongodb.pem: $(openssl base64 -A < mongo.pem)/" ../yaml-resources/mongo/01-mongo-federated-secret-mod.yaml' "1" "1"
  run_ok_or_fail 'sed -i "s/ca.pem: .*$/ca.pem: $(openssl base64 -A < ca.pem)/" ../yaml-resources/mongo/01-mongo-federated-secret-mod.yaml' "1" "1"
  echo "Crafting MongoDB OCP Deployment containing mongodb endpoints"
  run_ok_or_fail 'sed -i "s/primarynodehere/${ROUTE_CLUSTER1}:443/" ../yaml-resources/mongo/04-mongo-federated-deployment-rs-mod.yaml' "0" "1"
  run_ok_or_fail 'sed -i "s/replicamembershere/${ROUTE_CLUSTER1}:443,${ROUTE_CLUSTER2}:443,${ROUTE_CLUSTER3}:443/" ../yaml-resources/mongo/04-mongo-federated-deployment-rs-mod.yaml' "0" "1"
  echo "Crafting Pacman OCP Deployment containing mongodb endpoints"
  run_ok_or_fail 'sed -i "s/pacmanhosthere/${PACMAN_URL}/" ../yaml-resources/pacman/03-pacman-federated-ingress-mod.yaml' "0" "1"
  run_ok_or_fail 'sed -i "s/primarymongohere/${ROUTE_CLUSTER1}/" ../yaml-resources/pacman/07-pacman-federated-deployment-rs-mod.yaml' "0" "1"
  run_ok_or_fail 'sed -i "s/replicamembershere/${ROUTE_CLUSTER1},${ROUTE_CLUSTER2},${ROUTE_CLUSTER3}/" ../yaml-resources/pacman/07-pacman-federated-deployment-rs-mod.yaml' "0" "1"
  cd .. &> /dev/null
}

wait_for_pod_not_running()
{
  READY=0
  WAIT=0
  MAX_WAIT=300
  CLUSTER="$1"
  POD_NAMESPACE="$2"
  POD_NAME="$3"
  echo "Checking if pod ${POD_NAME} from namespace ${POD_NAMESPACE} on cluster ${CLUSTER} is terminated"
  DESIRED_PODS=0
  while [ $READY -eq 0 ]
  do
    CURRENT_PODS=$(oc --context=${CLUSTER} -n ${POD_NAMESPACE} get pods -l "name=${POD_NAME}" -o name | wc -l)
    if [ "0$CURRENT_PODS" -eq "0$DESIRED_PODS" ]
    then
      echo "No pods $POD_NAME running"
      READY=1
    else
      echo "There are pods $POD_NAME running, waiting for termination... [$WAIT/$MAX_WAIT]"
      sleep 5
      WAIT=$(expr $WAIT + 5)
    fi
    if [ $WAIT -ge $MAX_WAIT ]
    then
      echo "Timeout while waiting pod ${POD_NAME} from namespace ${POD_NAMESPACE} on cluster ${CLUSTER} to being terminated"
      exit 1
    fi
  done
}

wait_for_deployment_ready()
{
  READY=0
  WAIT=0
  MAX_WAIT=300
  CLUSTER="$1"
  DEPLOYMENT_NAMESPACE="$2"
  DEPLOYMENT_NAME="$3"
  echo "Checking if deployment ${DEPLOYMENT_NAME} from namespace ${DEPLOYMENT_NAMESPACE} on cluster ${CLUSTER} is ready"
  DESIRED_REPLICAS=$(oc --context=${CLUSTER} -n ${DEPLOYMENT_NAMESPACE} get deployment ${DEPLOYMENT_NAME} -o jsonpath='{ .spec.replicas }')
  while [ $READY -eq 0 ]
  do
    CLUSTER_REPLICAS_READY=$(oc --context=${CLUSTER} -n ${DEPLOYMENT_NAMESPACE} get deployment ${DEPLOYMENT_NAME} -o jsonpath='{ .status.readyReplicas }')
    if [ "0$CLUSTER_REPLICAS_READY" -eq "0$DESIRED_REPLICAS" ]
    then
      echo "Deployment is ready"
      READY=1
    else
      echo "Deployment is not ready yet, waiting... [$WAIT/$MAX_WAIT]"
      sleep 5
      WAIT=$(expr $WAIT + 5) 
    fi
    if [ $WAIT -ge $MAX_WAIT ]
    then
      echo "Timeout while waiting deployment ${DEPLOYMENT_NAME} from namespace ${DEPLOYMENT_NAMESPACE} on cluster ${CLUSTER} to become ready"
      exit 1
    fi
  done
}

wait_for_csv_completed()
{
  READY=0
  WAIT=0
  MAX_WAIT=300
  CLUSTER="$1"
  CSV_NAMESPACE="$2"
  CSV_NAME="$3"
  echo "Checking if CSV ${CSV_NAME} from namespace ${CSV_NAMESPACE} on cluster ${CLUSTER} succeeded"
  echo "Empty phase means the CSV has not been created yet"
  DESIRED_PHASE="Succeeded"
  while [ $READY -eq 0 ]
  do
    CSV_PHASE=$(oc --context=${CLUSTER} -n ${CSV_NAMESPACE} get csv ${CSV_NAME} -o jsonpath='{ .status.phase }' 2>/dev/null)
    if [ "0$DESIRED_PHASE" == "0$CSV_PHASE" ]
    then
      echo "CSV succeeded"
      READY=1
    else
      echo "CSV is not ready yet, current phase is: ${CSV_PHASE}, waiting... [$WAIT/$MAX_WAIT]"
      sleep 5
      WAIT=$(expr $WAIT + 5)
    fi
    if [ $WAIT -ge $MAX_WAIT ]
    then
      echo "Timeout while waiting CSV ${CSV_NAME} from namespace ${CSV_NAMESPACE} on cluster ${CLUSTER} to succeed"
      exit 1
    fi
  done
}

mongo_pacman_demo_cleanup()
{
  echo "Deleting Pacman resources"
  run_ok_or_fail "oc --context=feddemocl1 -n ${DEMO_NAMESPACE} delete federatedingress pacman" "0" "1" "1"
  run_ok_or_fail "oc --context=feddemocl1 -n ${DEMO_NAMESPACE} delete federateddeployment pacman" "0" "1" "1"
  run_ok_or_fail "oc --context=feddemocl1 -n ${DEMO_NAMESPACE} delete federatedservice pacman" "0" "1" "1"
  run_ok_or_fail "oc --context=feddemocl1 -n ${DEMO_NAMESPACE} delete federatedserviceaccount pacman" "0" "1" "1"
  run_ok_or_fail "oc --context=feddemocl1 -n ${DEMO_NAMESPACE} delete federatedclusterrolebinding pacman" "0" "1" "1"
  run_ok_or_fail "oc --context=feddemocl1 -n ${DEMO_NAMESPACE} delete federatedclusterroles.types.kubefed.k8s.io pacman" "0" "1" "1"
  run_ok_or_fail "oc --context=feddemocl1 -n ${DEMO_NAMESPACE} delete federatedclusterrole pacman" "0" "1" "1"
  run_ok_or_fail "oc --context=feddemocl1 -n ${DEMO_NAMESPACE} delete federatedsecret mongodb-users-secret" "0" "1" "1"
  echo "Deleting MongoDB resources"
  run_ok_or_fail "oc --context=feddemocl1 -n ${DEMO_NAMESPACE} delete federateddeployment mongo" "0" "1" "1"
  run_ok_or_fail "oc --context=feddemocl1 -n ${DEMO_NAMESPACE} delete federatedpersistentvolumeclaim mongo" "0" "1" "1"
  run_ok_or_fail "oc --context=feddemocl1 -n ${DEMO_NAMESPACE} delete federatedservice mongo" "0" "1" "1"
  run_ok_or_fail "oc --context=feddemocl1 -n ${DEMO_NAMESPACE} delete federatedsecret mongodb-secret" "0" "1" "1"
  run_ok_or_fail "oc --context=feddemocl1 -n ${DEMO_NAMESPACE} delete federatedsecret mongodb-ssl" "0" "1" "1"
  run_ok_or_fail "oc --context=feddemocl1 -n ${DEMO_NAMESPACE} delete route mongo" "0" "1" "1"
  run_ok_or_fail "oc --context=feddemocl2 -n ${DEMO_NAMESPACE} delete route mongo" "0" "1" "1"
  run_ok_or_fail "oc --context=feddemocl3 -n ${DEMO_NAMESPACE} delete route mongo" "0" "1" "1"
  run_ok_or_fail "oc --context=feddemocl1 delete federatednamespace ${DEMO_NAMESPACE}" "0" "1" "1"
  echo "Deleting Federation"
  echo "Disabling federated resources on Host Cluster (may take a while)"
  for type in namespaces ingresses.extensions secrets serviceaccounts services configmaps persistentvolumeclaims deployments.apps roles.rbac.authorization.k8s.io rolebindings.rbac.authorization.k8s.io clusterrolebindings.rbac.authorization.k8s.io clusterroles.rbac.authorization.k8s.io
  do
    run_ok_or_fail "./bin/kubefedctl disable "${type}" --host-cluster-context feddemocl1" "0" "1" "1"
  done
  echo "Deleting Subscription"
  run_ok_or_fail "oc --context=feddemocl1 -n kube-federation-system delete subscription federation" "0" "1"
  echo "Deleting ClusterServiceVersion"
  run_ok_or_fail "oc --context=feddemocl1 -n kube-federation-system delete csv kubefed-operator.${CSV_RELEASE}" "0" "1"
  echo "Deleting CatalogSourceConfig"
  run_ok_or_fail "oc --context=feddemocl1 -n openshift-marketplace delete catalogsourceconfig installed-federation-kube-federation-system" "0" "1"
  echo "Deleting OperatorGroup"
  run_ok_or_fail "oc --context=feddemocl1 -n kube-federation-system delete operatorgroup federation" "0" "1"
}

namespace_kubefed_cleanup()
{
  echo "Removing namespace from cluster"
  run_ok_or_fail "oc --context=feddemocl1 delete namespace kube-federation-system" "0" "1"
  run_ok_or_fail "oc --context=feddemocl2 delete namespace kube-federation-system" "0" "1"
  run_ok_or_fail "oc --context=feddemocl3 delete namespace kube-federation-system" "0" "1"
}


wait_for_input()
{
  if [ $CI_MODE -eq 0 ]
  then
    read -p "Press enter to continue"
  fi
}

simulate_pacman_play()
{
  PLAYER_NAME="$1"
  CLOUD_NAME="$2"
  ZONE_NAME="$3"
  HOST_NAME="$4"
  SCORE_POINTS="$5"
  LEVEL="$6"
  run_ok_or_fail "curl -X POST http://${PACMAN_URL}/highscores -H 'Content-Type: application/x-www-form-urlencoded' -d 'name=${PLAYER_NAME}&cloud=${CLOUD_NAME}&zone=${ZONE_NAME}&host=${HOST_NAME}&score=${SCORE_POINTS}&level=${LEVEL}'" "0" "1" 
}

check_ci_scores()
{
  echo "CI: Getting score list"
  SCORE_LIST=$(curl -s -X GET http://${PACMAN_URL}/highscores/list)
  echo "CI: Getting AWS Scores" 
  AWS_ENTRIES=$(echo $SCORE_LIST | ./bin/jq '.[] | select(.cloud | contains("AWS")).name' | tr -d "\"" | sort | awk 'NR > 1 { printf(",") } {printf "%s",$0}')
  AWS_WINNERS=$(echo $SCORE_LIST | ./bin/jq '.[] | select(.cloud | contains("AWS")).name')
  echo -ne "\nAWS Scores:\n"
  echo -ne "$AWS_WINNERS\n"
  echo "CI: Getting GCP Scores"
  GCP_ENTRIES=$(echo $SCORE_LIST | ./bin/jq '.[] | select(.cloud | contains("GCP")).name' | tr -d "\"" | sort | awk 'NR > 1 { printf(",") } {printf "%s",$0}')
  GCP_WINNERS=$(echo $SCORE_LIST | ./bin/jq '.[] | select(.cloud | contains("GCP")).name')
  echo -ne "\nGCP Scores:\n"
  echo -ne "$GCP_WINNERS\n"
  echo "CI: Getting Azure Scores"
  AZURE_ENTRIES=$(echo $SCORE_LIST | ./bin/jq '.[] | select(.cloud | contains("Azure")).name' | tr -d "\"" | sort | awk 'NR > 1 { printf(",") } {printf "%s",$0}')
  AZURE_WINNERS=$(echo $SCORE_LIST | ./bin/jq '.[] | select(.cloud | contains("Azure")).name')
  echo -ne "\nAzure Scores:\n"
  echo -ne "$AZURE_WINNERS\n"
  if [ "$AWS_ENTRIES" != "Joel,Nathan" ]
  then
    echo "CI: Pacman scores in AWS not found"
    exit 1
  fi
  if [ "$GCP_ENTRIES" != "Ash,Gary" ]
  then
    echo "CI: Pacman scores in GCP not found"
    exit 1
  fi
  if [ "$AZURE_ENTRIES" != "Roxas,Sora" ]
  then
    echo "CI: Pacman scores in Azure not found"
    exit 1
  fi
}

wait_for_mongodb_replicaset()
{
  READY=0
  WAIT=0
  MAX_WAIT=300
  CLUSTER="$1"
  NAMESPACE="$2"
  HEALTHY_MEMBERS="$3"
  echo "Checking if MongoDB Replicaset from namespace ${NAMESPACE} on cluster ${CLUSTER} is configured"
  while [ $READY -eq 0 ]
  do
    MONGO_POD=$(oc --context=${CLUSTER} -n ${NAMESPACE} get pod --selector="name=mongo" --output=jsonpath='{.items..metadata.name}')
    REPLICASET_STATUS=$(oc --context=${CLUSTER} -n ${NAMESPACE} exec ${MONGO_POD} -- bash -c 'mongo --norc --quiet --username=admin --password=$MONGODB_ADMIN_PASSWORD --host localhost admin --tls --tlsCAFile /opt/mongo-ssl/ca.pem --eval "JSON.stringify(rs.status())"')
    REPLICASET_HEALTHY_MEMBERS=$(echo $REPLICASET_STATUS | ./bin/jq -n '[inputs | .members[].health] | reduce .[] as $num (0; .+$num)' 2>/dev/null)
    if [ "0$HEALTHY_MEMBERS" == "0$REPLICASET_HEALTHY_MEMBERS" ]
    then
      echo "MongoDB Replicaset is ready"
      READY=1
    else
      echo "MongoDB Replicaset is not ready yet, waiting... [$WAIT/$MAX_WAIT]"
      sleep 10
      WAIT=$(expr $WAIT + 5)
    fi
    if [ $WAIT -ge $MAX_WAIT ]
    then
      echo "Timeout while waiting MongoDB replicaset from namespace ${NAMESPACE} on cluster ${CLUSTER} to be configured"
      exit 1
    fi
  done
}

check_ci_replicaset()
{
  MEMBER_CLUSTER1="mongo-${DEMO_NAMESPACE}.apps.${CLUSTER1_URL}:443"
  MEMBER_CLUSTER2="mongo-${DEMO_NAMESPACE}.apps.${CLUSTER2_URL}:443"
  MEMBER_CLUSTER3="mongo-${DEMO_NAMESPACE}.apps.${CLUSTER3_URL}:443"
  MONGO_POD_CL1=$(oc --context=feddemocl1 -n ${DEMO_NAMESPACE} get pod --selector="name=mongo" --output=jsonpath='{.items..metadata.name}')
  REPLICASET_STATUS=$(oc --context=feddemocl1 -n ${DEMO_NAMESPACE} exec $MONGO_POD_CL1 -- bash -c 'mongo --norc --quiet --username=admin --password=$MONGODB_ADMIN_PASSWORD --host localhost admin --tls --tlsCAFile /opt/mongo-ssl/ca.pem --eval "JSON.stringify(rs.status())"')
  echo "CI: Getting MongoDB Replica Status on 1st Cluster"
  MEMBER_CLUSTER1_HEALTH=$(echo $REPLICASET_STATUS | ./bin/jq --arg CL1 $MEMBER_CLUSTER1 '.members[] | select(.name | contains ($CL1)).health')
  echo "  Health: $MEMBER_CLUSTER1_HEALTH"
  echo "CI: Getting MongoDB Replica Status on 2nd Cluster"
  MEMBER_CLUSTER2_HEALTH=$(echo $REPLICASET_STATUS | ./bin/jq --arg CL1 $MEMBER_CLUSTER2 '.members[] | select(.name | contains ($CL1)).health')
  echo "  Health: $MEMBER_CLUSTER2_HEALTH"
  echo "CI: Getting MongoDB Replica Status on 3rd Cluster"
  MEMBER_CLUSTER3_HEALTH=$(echo $REPLICASET_STATUS | ./bin/jq --arg CL1 $MEMBER_CLUSTER3 '.members[] | select(.name | contains ($CL1)).health')
  echo "  Health: $MEMBER_CLUSTER3_HEALTH"
  echo "CI: Getting MongoDB Healthy Members"
  HEALTHY_MEMBERS_COUNT=$(echo $REPLICASET_STATUS | ./bin/jq '.members[] | select(.health | contains(1)).name' | wc -l)
  HEALTHY_MEMBERS=$(echo $REPLICASET_STATUS | ./bin/jq '.members[] | select(.health | contains(1)).name')
  echo -ne "\nHealthy Members:\n"
  echo -ne "$HEALTHY_MEMBERS\n"
  echo "CI: Getting MongoDB Primary Member"
  PRIMARY_MEMBERS_COUNT=$(echo $REPLICASET_STATUS | ./bin/jq '.members[] | select(.state | contains(1)).name' | wc -l)
  PRIMARY_MEMBERS=$(echo $REPLICASET_STATUS | ./bin/jq '.members[] | select(.state | contains(1)).name')
  echo -ne "\nPrimary Member:\n"
  echo -ne "$PRIMARY_MEMBERS\n"
  echo "CI: Getting MongoDB Secondary Members"
  SECONDARY_MEMBERS_COUNT=$(echo $REPLICASET_STATUS | ./bin/jq '.members[] | select(.state | contains(2)).name' | wc -l)
  SECONDARY_MEMBERS=$(echo $REPLICASET_STATUS | ./bin/jq '.members[] | select(.state | contains(2)).name')
  echo -ne "\nSecondary Members:\n"
  echo -ne "$SECONDARY_MEMBERS\n"
  if [ "0$MEMBER_CLUSTER1_HEALTH" -ne "01" ]
  then
    echo "CI: MongoDB Replica $MEMBER_CLUSTER1 unhealthy"
    exit 1
  fi
  if [ "0$MEMBER_CLUSTER2_HEALTH" -ne "01" ]
  then
    echo "CI: MongoDB Replica $MEMBER_CLUSTER2 unhealthy"
    exit 1
  fi
  if [ "0$MEMBER_CLUSTER3_HEALTH" -ne "01" ]
  then
    echo "CI: MongoDB Replica $MEMBER_CLUSTER3 unhealthy"
    exit 1
  fi
  if [ "0$HEALTHY_MEMBERS_COUNT" -ne "03" ]
  then
    echo "CI: Unhealthy MongoDB ReplicaSet members found"
    exit 1
  fi
  if [ "0$PRIMARY_MEMBERS_COUNT" -ne "01" ]
  then
    echo "CI: Primary MongoDB Replica member not found"
    exit 1
  fi
  if [ "0$SECONDARY_MEMBERS_COUNT" -ne "02" ]
  then
    echo "CI: Secondaries MongoDB Replica members not found"
    exit 1
  fi
}

mongo_pacman_demo()
{
  ROUTE_CLUSTER1="mongo-${DEMO_NAMESPACE}.apps.${CLUSTER1_URL}"
  ROUTE_CLUSTER2="mongo-${DEMO_NAMESPACE}.apps.${CLUSTER2_URL}"
  ROUTE_CLUSTER3="mongo-${DEMO_NAMESPACE}.apps.${CLUSTER3_URL}"
  echo "1. At this point we have the "${DEMO_NAMESPACE}" Namespace across three different clusters (Cluster1, Cluster2 and Cluster3)" 
  run_ok_or_fail 'for cluster in feddemocl1 feddemocl2 feddemocl3;do echo **Cluster ${cluster}**;oc --context=$cluster get namespaces ${DEMO_NAMESPACE};done' "1" "1"
  echo "2. A federatedSecret will be created across the federated clusters, the secrets include the certificates and user/password details"
  wait_for_input
  run_ok_or_fail "oc --context=feddemocl1 -n ${DEMO_NAMESPACE} create -f yaml-resources/mongo/01-mongo-federated-secret-mod.yaml" "0" "1"
  sleep 3
  run_ok_or_fail 'for cluster in feddemocl1 feddemocl2 feddemocl3;do echo **Cluster ${cluster}**;oc --context=$cluster -n ${DEMO_NAMESPACE} get secrets | grep mongodb;done' "1" "1"
  echo "3. We need a service on each cluster, so we are going to create a federatedservice for that purpouse"
  wait_for_input
  run_ok_or_fail "oc --context=feddemocl1 -n ${DEMO_NAMESPACE} create -f yaml-resources/mongo/02-mongo-federated-service.yaml" "0" "1"
  sleep 3
  run_ok_or_fail 'for cluster in feddemocl1 feddemocl2 feddemocl3;do echo **Cluster ${cluster}**;oc --context=$cluster -n ${DEMO_NAMESPACE} get services --selector="name=mongo";done' "1" "1" 
  echo "4. Our deployment needs a volume in order to store the MongoDB data, so let's create the Federated resource definition, that will end in a PVC attached to a PV on each cluster"
  wait_for_input
  run_ok_or_fail "oc --context=feddemocl1 -n ${DEMO_NAMESPACE} create -f yaml-resources/mongo/03-mongo-federated-pvc.yaml" "0" "1"
  sleep 3
  run_ok_or_fail 'for cluster in feddemocl1 feddemocl2 feddemocl3;do echo **Cluster ${cluster}**;oc --context=$cluster -n ${DEMO_NAMESPACE} get pvc mongo;done' "1" "1"
  echo "5. Now, we are ready to deploy the mongodb replicas, for this demo we will be federating a deployment with one replica. So we will have three mongodb pods, one pod on each cluster"
  wait_for_input
  run_ok_or_fail "oc --context=feddemocl1 -n ${DEMO_NAMESPACE} create -f yaml-resources/mongo/04-mongo-federated-deployment-rs-mod.yaml" "0" "1"
  sleep 3
  run_ok_or_fail 'for cluster in feddemocl1 feddemocl2 feddemocl3;do echo **Cluster ${cluster}**;oc --context=$cluster -n ${DEMO_NAMESPACE} get pods --selector="name=mongo";done' "1" "1"
  echo "6. Finally, we need to create the routes in order to get external traffic to our pods, these routes will be passthrough as we need mongo to handle the certs and the connection to remain TLS rather than HTTPS"
  wait_for_input
  run_ok_or_fail "oc --context=feddemocl1 -n ${DEMO_NAMESPACE} create route passthrough mongo --service=mongo --port=27017 --hostname=${ROUTE_CLUSTER1}" "0" "1"
  run_ok_or_fail "oc --context=feddemocl2 -n ${DEMO_NAMESPACE} create route passthrough mongo --service=mongo --port=27017 --hostname=${ROUTE_CLUSTER2}" "0" "1"
  run_ok_or_fail "oc --context=feddemocl3 -n ${DEMO_NAMESPACE} create route passthrough mongo --service=mongo --port=27017 --hostname=${ROUTE_CLUSTER3}" "0" "1"
  echo "7. Next we are going to configure the mongodb replicaset, this procedure has been automated and the only thing you need to do is label the primary pod, in this case Cluster1"
  wait_for_input
  wait_for_deployment_ready "feddemocl1" "${DEMO_NAMESPACE}" "mongo"
  wait_for_deployment_ready "feddemocl2" "${DEMO_NAMESPACE}" "mongo"
  wait_for_deployment_ready "feddemocl3" "${DEMO_NAMESPACE}" "mongo"
  MONGO_POD=$(oc --context=feddemocl1 -n ${DEMO_NAMESPACE} get pod --selector="name=mongo" --output=jsonpath='{.items..metadata.name}')
  run_ok_or_fail "oc --context=feddemocl1 -n ${DEMO_NAMESPACE} label pod $MONGO_POD replicaset=primary" "0" "1"
  wait_for_mongodb_replicaset "feddemocl1" "${DEMO_NAMESPACE}" "3"
  oc --context=feddemocl1 -n ${DEMO_NAMESPACE} exec $MONGO_POD -- bash -c 'mongo --norc --quiet --username=admin --password=$MONGODB_ADMIN_PASSWORD --host localhost admin --tls --tlsCAFile /opt/mongo-ssl/ca.pem --eval "rs.status()"'
  echo "8. Now we are going to deploy Pacman and connect it to the MongoDB Replicaset. Let's start creating a federatedsecret to store the database connection details"
  wait_for_input
  run_ok_or_fail "oc --context=feddemocl1 -n ${DEMO_NAMESPACE} create -f yaml-resources/pacman/01-mongo-federated-secret.yaml" "0" "1"
  echo "9. As we did before, Pacman needs some services to be created"
  wait_for_input
  run_ok_or_fail "oc --context=feddemocl1 -n ${DEMO_NAMESPACE} create -f yaml-resources/pacman/02-pacman-federated-service.yaml" "0" "1"
  echo "10. We need a route for our Pacman application, let's create a FederatedIngress that points to our LoadBalancer"
  wait_for_input
  run_ok_or_fail "oc --context=feddemocl1 -n ${DEMO_NAMESPACE} create -f yaml-resources/pacman/03-pacman-federated-ingress-mod.yaml" "0" "1"
  echo "11. We need a route for our Pacman application, let's create a FederatedIngress that points to our LoadBalancer"
  wait_for_input
  run_ok_or_fail "oc --context=feddemocl1 -n ${DEMO_NAMESPACE} create -f yaml-resources/pacman/04-pacman-federated-service-account.yaml" "0" "1"
  echo "12. A service account is created to be used with the deployment of the pacman application."
  wait_for_input
  run_ok_or_fail "oc --context=feddemocl1 -n ${DEMO_NAMESPACE} create -f yaml-resources/pacman/05-pacman-federated-cluster-role.yaml" "0" "1"
  echo "13. We need a cluster role to allow for the pacman application to interact with the Kubernetes API."
  wait_for_input
  run_ok_or_fail "oc --context=feddemocl1 -n ${DEMO_NAMESPACE} create -f yaml-resources/pacman/06-pacman-federated-cluster-role-binding.yaml" "0" "1"
  echo "14. With the cluster role in place we need to bind the service account with the cluster role."
  wait_for_input
  run_ok_or_fail "oc --context=feddemocl1 -n ${DEMO_NAMESPACE} create -f yaml-resources/pacman/07-pacman-federated-deployment-rs-mod.yaml" "0" "1"
  wait_for_deployment_ready "feddemocl1" "${DEMO_NAMESPACE}" "pacman"
  wait_for_deployment_ready "feddemocl2" "${DEMO_NAMESPACE}" "pacman"
  wait_for_deployment_ready "feddemocl3" "${DEMO_NAMESPACE}" "pacman"
  run_ok_or_fail 'for cluster in feddemocl1 feddemocl2 feddemocl3;do echo **Cluster ${cluster}**;oc --context=$cluster -n ${DEMO_NAMESPACE} get pods --selector="name=pacman";done' "1" "1"
  echo "15. Go play Pacman and save some highscores. http://${PACMAN_URL} (Note: Pretend you're bad at Pacman)"
  wait_for_input
  if [ $CI_MODE -eq 1 ]
  then
    simulate_pacman_play "Nathan" "AWS" "us-east-1a" "padman-pod-1" "288" "1"
    sleep 3
    simulate_pacman_play "Joel" "AWS" "us-west-1a" "padman-pod-2" "196" "1"
  fi
  echo "16. Well, everything should be working fine. Let's create some chaos, what will happen if primary mongo pod gets deleted?"
  wait_for_input
  PATCH='{"spec":{"overrides":[{"clusterName":"feddemocl1","clusterOverrides":[{"path":"/spec/replicas","value":0}]}]}}'
  run_ok_or_fail "oc --context=feddemocl1 -n ${DEMO_NAMESPACE} patch federateddeployment mongo --type=merge -p '${PATCH}'" "0" "1"
  wait_for_pod_not_running "feddemocl1" "${DEMO_NAMESPACE}" "mongo"
  PATCH='{"spec":{"placement":{"clusters":[{"name":"feddemocl2"},{"name":"feddemocl3"}]}}}'
  run_ok_or_fail "oc --context=feddemocl1 -n ${DEMO_NAMESPACE} patch federatedpersistentvolumeclaims mongo --type=merge -p '${PATCH}'" "0" "1"
  run_ok_or_fail "oc --context=feddemocl1 -n ${DEMO_NAMESPACE} get pods --selector='name=mongo'" "1" "1"
  echo "17. Let's continue playing and see if we can save highscores. http://${PACMAN_URL}. (Note: Saving the high score could take longer than usual)"
  wait_for_input
  if [ $CI_MODE -eq 1 ]
  then
    simulate_pacman_play "Ash" "GCP" "us-east-1b" "padman-pod-1" "150" "1"    
    sleep 3
    simulate_pacman_play "Gary" "GCP" "us-west-1b" "padman-pod-2" "149" "1"
  fi
  echo "18. Well, our Pacman application is not that famous, let's scale it so it only runs on one of our clusters"
  PATCH='{"spec":{"overrides":[{"clusterName":"feddemocl1","clusterOverrides":[{"path":"/spec/replicas","value":0}]},{"clusterName":"feddemocl3","clusterOverrides":[{"path":"spec.replicas","value":0}]}]}}'
  run_ok_or_fail "oc --context=feddemocl1 -n ${DEMO_NAMESPACE} patch federateddeployment pacman --type=merge -p '${PATCH}'" "0" "1"
  sleep 3
  run_ok_or_fail 'for cluster in feddemocl1 feddemocl2 feddemocl3;do echo **Cluster ${cluster}**;oc --context=$cluster -n ${DEMO_NAMESPACE} get pods --selector="name=pacman";done' "1" "1"
  echo "19. Our engineers have been working hard during the weekend and the cluster where the primary mongo pod was deployed came back to life"
  wait_for_input
  PATCH='{"spec":{"placement":{"clusters":[{"name":"feddemocl1"},{"name":"feddemocl2"},{"name":"feddemocl3"}]}}}'
  run_ok_or_fail "oc --context=feddemocl1 -n ${DEMO_NAMESPACE} patch federatedpersistentvolumeclaims mongo --type=merge -p '${PATCH}'" "0" "1"
  sleep 3
  PATCH='{"spec":{"overrides":[]}}'
  run_ok_or_fail "oc --context=feddemocl1 -n ${DEMO_NAMESPACE} patch federateddeployment mongo --type=merge -p '${PATCH}'" "0" "1"
  sleep 3
  run_ok_or_fail "oc --context=feddemocl1 -n ${DEMO_NAMESPACE} get pods --selector='name=mongo'" "1" "1"
  echo "20. Our Pacman application has become trendy among teenagers, they don't want to play Fortnite anymore. We need to scale!!"
  wait_for_input
  PATCH='{"spec":{"overrides":[]}}'
  run_ok_or_fail "oc --context=feddemocl1 -n ${DEMO_NAMESPACE} patch federateddeployment pacman --type=merge -p '${PATCH}'" "0" "1"
  wait_for_deployment_ready "feddemocl1" "${DEMO_NAMESPACE}" "pacman"
  wait_for_deployment_ready "feddemocl2" "${DEMO_NAMESPACE}" "pacman"
  wait_for_deployment_ready "feddemocl3" "${DEMO_NAMESPACE}" "pacman"
  run_ok_or_fail 'for cluster in feddemocl1 feddemocl2 feddemocl3;do echo **Cluster ${cluster}**;oc --context=$cluster -n ${DEMO_NAMESPACE} get pods --selector="name=pacman";done' "1" "1"
  echo "21. Bonus track: We should see our MongoDB Replica being restored"
  wait_for_deployment_ready "feddemocl1" "${DEMO_NAMESPACE}" "mongo"
  wait_for_mongodb_replicaset "feddemocl1" "${DEMO_NAMESPACE}" "3"
  run_ok_or_fail "oc --context=feddemocl1 -n ${DEMO_NAMESPACE} get pods -o name --selector='name=mongo' | xargs oc --context=feddemocl1 -n ${DEMO_NAMESPACE} logs" "1" "1"
  if [ $CI_MODE -eq 1 ]
  then
    sleep 3
    simulate_pacman_play "Sora" "Azure" "us-east-1a" "padman-pod-1" "300" "1"         
    sleep 3
    simulate_pacman_play "Roxas" "Azure" "us-west-1b" "padman-pod-2" "299" "1"
  fi
  echo "Demo finished. Questions?"
}

check_mode()
{
  MODE_TO_RUN=$1
  DEMO=0
  DEMO_CLEANUP=0
  FULL_CLEANUP=0
  if [ "$MODE_TO_RUN" == "demo" ]
  then
    DEMO=1 
  elif [ "$MODE_TO_RUN" == "demo-cleanup" ]
  then
    DEMO_CLEANUP=1
  elif [ "$MODE_TO_RUN" == "full-cleanup" ]
  then
    FULL_CLEANUP=1
  else
      echo "Invalid mode $MODE_TO_CHECK, valid modes: [demo|demo-cleanup|full-cleanup]"
      exit 1
  fi
}

check_steps()
{
  STEPS_TO_RUN=$1
  RUN_CONTEXT_CREATION=0
  RUN_SETUP_KUBEFED=0
  RUN_SETUP_MONGO=0
  RUN_DEMO_ONLY=0
  for STEP_TO_CHECK in $(echo $STEPS_TO_RUN | sed "s/,/ /g")
  do
    if [ "$STEP_TO_CHECK" == "context-creation" ]
    then
      RUN_CONTEXT_CREATION=1 
    elif [ "$STEP_TO_CHECK" == "setup-kubefed" ]
    then
      RUN_SETUP_KUBEFED=1
    elif [ "$STEP_TO_CHECK" == "setup-mongo-tls" ]
    then
      RUN_SETUP_MONGO=1
    elif [ "$STEP_TO_CHECK" == "demo-only" ]
    then
      RUN_DEMO_ONLY=1
    elif [ "$STEP_TO_CHECK" == "all" ]
    then
      RUN_CONTEXT_CREATION=1
      RUN_SETUP_KUBEFED=1
      RUN_SETUP_MONGO=1
      RUN_DEMO_ONLY=1
      break
    else
      echo "Invalid step $STEP_TO_CHECK, valid steps: [context-creation|setup-kubefed|setup-mongo-tls|demo-only]"
      exit 1
    fi
  done
}

main()
{
  check_mode $MODE
  check_steps $STEPS
  check_tools
  get_input_data
  if [ "$MODE" == "demo" ]
  then
    wait_for_input
    if [ $RUN_CONTEXT_CREATION -eq 1 ]
    then
      echo "We are going to create three contexts into our oc tool config"
      context_creation "feddemocl1" ${CLUSTER1_API_URL} ${CLUSTER1_ADMIN} ${CLUSTER1_ADMIN_PWD} 
      context_creation "feddemocl2" ${CLUSTER2_API_URL} ${CLUSTER2_ADMIN} ${CLUSTER2_ADMIN_PWD} 
      context_creation "feddemocl3" ${CLUSTER3_API_URL} ${CLUSTER3_ADMIN} ${CLUSTER3_ADMIN_PWD} 
    fi
    if [ $RUN_SETUP_KUBEFED -eq 1 ]
    then
      echo -ne "\n\n\nNow it's time to deploy Kubefed\n"
      setup_kubefed
    fi
    if [ $RUN_SETUP_MONGO -eq 1 ]
    then
      echo -ne "\n\n\nMongoDB replicas will communicate with each other using TLS, so we are going to create the required certificates\n"
      setup_mongo_tls
    fi
    if [ $RUN_DEMO_ONLY -eq 1 ]
    then
      echo -ne "\n\n\nWe're ready to deploy MongoDB ReplicaSet across our clusters and then deploy Pacman\n"
      wait_for_input
      clear
      mongo_pacman_demo
    fi
    if [ $CI_MODE -eq 1 ]
    then
      echo -ne "\n\n\nRunning CI tests\n"
      download_jq_binary
      check_ci_scores
      check_ci_replicaset
    fi
  else
    if [ $RUN_CONTEXT_CREATION -eq 1 ]
    then
      echo "We are going to create three contexts into our oc tool config"
      context_creation "feddemocl1" ${CLUSTER1_API_URL} ${CLUSTER1_ADMIN} ${CLUSTER1_ADMIN_PWD}
      context_creation "feddemocl2" ${CLUSTER2_API_URL} ${CLUSTER2_ADMIN} ${CLUSTER2_ADMIN_PWD}
      context_creation "feddemocl3" ${CLUSTER3_API_URL} ${CLUSTER3_ADMIN} ${CLUSTER3_ADMIN_PWD}
      if [[ "$MODE" == "demo-cleanup" || "$MODE" == "full-cleanup" ]]
      then
        echo "Cleaning up demo resources"
        mongo_pacman_demo_cleanup
      fi
      if [ "$MODE" == "full-cleanup" ]
      then
        namespace_kubefed_cleanup
      fi
    fi
  fi
}

ARGS_ARRAY=( "$@" )
ARGS=1

for arg in $@; do
    case $arg in
        -m | --mode )           
                                MODE=${ARGS_ARRAY[$ARGS]}
                                ;;
        -s | --steps )          
                                STEPS=${ARGS_ARRAY[$ARGS]}
                                ;;
        -n | --namespace)
                                DEMO_NAMESPACE=${ARGS_ARRAY[$ARGS]}
                                ;;
        --ci-mode )
                                CI_MODE=1
                                ;;
        -h | --help )           
                                usage
                                exit 0
                                ;;
    esac
    ARGS=$(expr $ARGS + 1)
done

STEPS=${STEPS:="all"}
MODE=${MODE:="demo"}
CI_MODE=${CI_MODE:="0"}
DEMO_NAMESPACE=${DEMO_NAMESPACE:="federation-demo"}

main
