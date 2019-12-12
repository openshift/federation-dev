#!/bin/bash

# GLOBAL VAR
ARGOCD_NAMESPACE="argocd"
GOGS_NAMESPACE="federation-demo-gogs"
HAPROXY_NAMESPACE="federation-demo-haproxy"
ARGOCD_RELEASE="v1.3.6"

usage()
{
  echo "$0 [-m|--mode MODE] [-s|--steps STEPS]"
  echo -ne "\noptions:\n"
  echo "-m|--mode - Accepted values: [demo|full-cleanup|demo-cleanup]." 
  echo "  Demo will perform the demo, demo-cleanup will delete mongo and pacman resources"
  echo "  full-cleanup will delete everything including the namespace where the demo was deployed. Default value: demo"
  echo "-s|--steps - Accepted values: [context-creation|setup-argocd|setup-gogs|load-git-content|demo-only]."
  echo "  Any combination of these separated by commas will run only those steps. Default value: all"
  echo "-n|--namespace - Accepted values: name of the namespace where the demo will be deployed. Default value: federation-demo"
  echo "  e.g: my-pacman-demo"
  echo "--ci-mode"
  echo "  The script will run in CI mode, which means no user interaction is needed"
  echo -ne "\nexamples:\n"
  echo "run everything (default): $0"
  echo "cleanup demo resources: $0 -m demo-cleanup"
  echo "run only the demo steps: $0 -s demo-only"
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
}

get_input_data()
{
  INVENTORY_FILE="./inventory.json"
  if [ -s ${INVENTORY_FILE} ]
  then
    get_data_from_inventory ${INVENTORY_FILE}
  else
    echo "Inventory file ${INVENTORY_FILE} not found. Exiting..."
    exit 1
  fi
}

download_cfssl_tools()
{
  if [ ! -s "bin/cfssl" ]
  then
    echo "Downloading cfssl binary"
    run_ok_or_fail "curl -Ls https://pkg.cfssl.org/R1.2/cfssl_linux-amd64 -o bin/cfssl && chmod +x bin/cfssl" "0" "1"
  fi
  if [ ! -s "bin/cfssljson" ]
  then
    echo "Downloading cfssljson binary"
    run_ok_or_fail "curl -Ls https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64 -o bin/cfssljson && chmod +x bin/cfssljson" "0" "1"
  fi
}

download_jq_binary()
{
  if [ ! -s "bin/jq" ]
  then
    echo "Downloading jq tool binary"
    run_ok_or_fail "curl -Ls https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 -o bin/jq && chmod +x bin/jq" "0" "1"
  fi
}

download_argocd_binary()
{
  if [ ! -s "bin/argocd" ]
  then
    echo "Download argocd binary"
    run_ok_or_fail "curl -Ls https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_RELEASE}/argocd-linux-amd64 -o bin/argocd && chmod +x bin/argocd"
  fi
}

create_annotated_namespace()
{
  NS_NAME="$1"
  NAMESPACE_CHECK=$(oc --context=feddemocl1 get ns ${NS_NAME} -o name 2>/dev/null | wc -l)
  NAMESPACE_ALREADY_EXISTS=0
  if [ "0${NAMESPACE_CHECK}" == "01" ]
  then
    NAMESPACE_ALREADY_EXISTS=1
  else
    run_ok_or_fail "oc --context=feddemocl1 create ns ${NS_NAME}" "0" "1"
    run_ok_or_fail "oc --context=feddemocl1 annotate namespace ${NS_NAME} auto-demo='${DEMO_NAMESPACE}'" "0" "1"
  fi
  echo ${NAMESPACE_ALREADY_EXISTS}
}

delete_annotated_namespace()
{
  CLUSTER="$1"
  NAMESPACE="$2"
  NAMESPACE_ANNOTATION=$(oc --context=${CLUSTER} get ns ${NAMESPACE} -o "jsonpath={.metadata.annotations['auto-demo']}" 2>/dev/null)
  if [ "0${NAMESPACE_ANNOTATION}" == "0${DEMO_NAMESPACE}" ]
  then
    echo "1"
  fi
}

get_clusters_wilcard_domain()
{
  for cluster in feddemocl1 feddemocl2 feddemocl3
  do
    oc --context=$cluster -n default create route edge wildcarddomain --service=test --port=8080 > /dev/null
  done
  WILDCARD_DOMAIN_CL1=$(oc --context=feddemocl1 -n default get route wildcarddomain -o jsonpath='{.status.ingress[*].host}' | sed "s/wildcarddomain-default.\(.*\)/\1/g")
  WILDCARD_DOMAIN_CL2=$(oc --context=feddemocl2 -n default get route wildcarddomain -o jsonpath='{.status.ingress[*].host}' | sed "s/wildcarddomain-default.\(.*\)/\1/g")
  WILDCARD_DOMAIN_CL3=$(oc --context=feddemocl3 -n default get route wildcarddomain -o jsonpath='{.status.ingress[*].host}' | sed "s/wildcarddomain-default.\(.*\)/\1/g")
  for cluster in feddemocl1 feddemocl2 feddemocl3
  do
    oc --context=$cluster -n default delete route wildcarddomain > /dev/null
  done
}

setup_haproxy()
{
  HAPROXY_NAMESPACE_ALREADY_EXISTS=$(create_annotated_namespace $HAPROXY_NAMESPACE)
  if [ "0${HAPROXY_NAMESPACE_ALREADY_EXISTS}" == "01" ]
  then
    echo "${HAPROXY_NAMESPACE} namespace already exists in the cluster. We cannot proceed with the demo."
    exit 1
  else
    echo "Namespace ${HAPROXY_NAMESPACE} created for deploying the HAProxy Load Balancer."
  fi
  echo "Deploying HAProxy on feddemocl1 cluster in namespace ${HAPROXY_NAMESPACE}"
  HAPROXY_LB_ROUTE=pacman-multicluster.${WILDCARD_DOMAIN_CL1}
  PACMAN_INGRESS=pacman-ingress.${WILDCARD_DOMAIN_CL1}
  run_ok_or_fail "oc --context=feddemocl1 -n ${HAPROXY_NAMESPACE} create route edge haproxy-lb --service=haproxy-lb-service --port=8080 --insecure-policy=Allow --hostname=${HAPROXY_LB_ROUTE}" "0" "1"
  PACMAN_CLUSTER1=pacman.${WILDCARD_DOMAIN_CL1}
  PACMAN_CLUSTER2=pacman.${WILDCARD_DOMAIN_CL2}
  PACMAN_CLUSTER3=pacman.${WILDCARD_DOMAIN_CL3}
  cp -pf yaml-resources/haproxy/haproxy.tmpl yaml-resources/haproxy/haproxy
  run_ok_or_fail 'sed -i "/option httpchk GET/a \ \ \ \ http-request set-header Host ${PACMAN_INGRESS}" yaml-resources/haproxy/haproxy'
  run_ok_or_fail 'sed -i "s/<pacman_lb_hostname>/${PACMAN_INGRESS}/g" yaml-resources/haproxy/haproxy'
  run_ok_or_fail 'sed -i "s/<server1_name> <server1_pacman_route>:<route_port>/cluster1 ${PACMAN_CLUSTER1}:80/g" yaml-resources/haproxy/haproxy'
  run_ok_or_fail 'sed -i "s/<server2_name> <server2_pacman_route>:<route_port>/cluster2 ${PACMAN_CLUSTER2}:80/g" yaml-resources/haproxy/haproxy'
  run_ok_or_fail 'sed -i "s/<server3_name> <server3_pacman_route>:<route_port>/cluster3 ${PACMAN_CLUSTER3}:80/g" yaml-resources/haproxy/haproxy'
  run_ok_or_fail "oc --context=feddemocl1 -n ${HAPROXY_NAMESPACE} create configmap haproxy --from-file=yaml-resources/haproxy/haproxy"
  run_ok_or_fail "oc --context=feddemocl1 -n ${HAPROXY_NAMESPACE} create -f yaml-resources/haproxy/haproxy-clusterip-service.yaml"
  run_ok_or_fail "oc --context=feddemocl1 -n ${HAPROXY_NAMESPACE} create -f yaml-resources/haproxy/haproxy-deployment.yaml"
  echo "HAProxy setup completed"
}

add_cluster_to_argo()
{
  CLUSTER_TO_JOIN="$1"
  ./bin/argocd cluster add ${CLUSTER_TO_JOIN} &> /tmp/clusteradd
  if [ $? -ne 0 ]
  then
    SECRET_NAME=$(cat /tmp/clusteradd | grep Secret | perl -pe 's|.*?(argocd-manager-dockercfg-.*?)\\.*|\1|')
    oc --context ${CLUSTER_TO_JOIN} -n kube-system delete secret ${SECRET_NAME} &> /dev/null
    ./bin/argocd cluster add ${CLUSTER_TO_JOIN} &> /tmp/clusteradd
    rm /tmp/clusteradd
  fi
}

setup_argocd()
{
  ARGOCD_NAMESPACE_ALREADY_EXISTS=$(create_annotated_namespace $ARGOCD_NAMESPACE)
  if [ "0${ARGOCD_NAMESPACE_ALREADY_EXISTS}" == "01" ]
  then
    echo "${ARGOCD_NAMESPACE} namespace already exists in the cluster. We cannot proceed with the demo"
    exit 1
  else
    echo "Namespace ${ARGOCD_NAMESPACE} created for deplying the Argo CD Server."
  fi
  download_argocd_binary
  echo "Deploying Argo CD Server on Cluster1 in namespace ${ARGOCD_NAMESPACE}"
  run_ok_or_fail "oc --context feddemocl1 -n ${ARGOCD_NAMESPACE} apply -f yaml-resources/argocd/argocd-install.yaml" "0" "1"
  wait_for_deployment_ready "feddemocl1" "${ARGOCD_NAMESPACE}" "argocd-server" "0"
  echo "Expose Argo CD Server with an OpenShift Route"
  run_ok_or_fail "oc --context feddemocl1 -n ${ARGOCD_NAMESPACE} create route edge argocd-server --service=argocd-server --port=http --insecure-policy=Redirect" "0" "1"
  echo "Initializing Argo CD admin user"
  ARGOCD_SERVER_PASSWORD=$(oc --context feddemocl1 -n ${ARGOCD_NAMESPACE} get pod -l "app.kubernetes.io/name=argocd-server" -o jsonpath='{.items[*].metadata.name}')
  ARGOCD_SERVER_ROUTE=$(oc --context feddemocl1 -n ${ARGOCD_NAMESPACE} get route argocd-server -o jsonpath='{.spec.host}')
  sleep 2
  run_ok_or_fail "./bin/argocd --insecure --grpc-web login ${ARGOCD_SERVER_ROUTE}:443 --username admin --password ${ARGOCD_SERVER_PASSWORD}" "0" "1"
  sleep 2
  run_ok_or_fail "./bin/argocd --insecure --grpc-web --server ${ARGOCD_SERVER_ROUTE}:443 account update-password --current-password ${ARGOCD_SERVER_PASSWORD} --new-password admin" "0" "1"
  echo "Add clusters to Argo CD Server"
  add_cluster_to_argo "feddemocl1"
  add_cluster_to_argo "feddemocl2"
  add_cluster_to_argo "feddemocl3"
  run_ok_or_fail "./bin/argocd cluster list" "1" "1"
  echo "feddemocl1 - ${CLUSTER1_URL}"
  echo "feddemocl2 - ${CLUSTER2_URL}"
  echo "feddemocl3 - ${CLUSTER3_URL}"
  echo "Argo CD setup completed"
}

setup_gogs()
{
  GOGS_NAMESPACE_ALREADY_EXISTS=$(create_annotated_namespace $GOGS_NAMESPACE)
  if [ "0${GOGS_NAMESPACE_ALREADY_EXISTS}" == "01" ]
  then
    echo "${GOGS_NAMESPACE} namespace already exists in the cluster. We cannot proceed with the demo."
    exit 1
  else
    echo "Namespace ${GOGS_NAMESPACE} created for deploying the Gogs Git Server."
  fi
  echo "Deploying Gogs Git Server on feddemocl1 cluster in namespace ${GOGS_NAMESPACE}"
  GOGS_ROUTE=gogs-demo.${WILDCARD_DOMAIN_CL1}
  run_ok_or_fail "oc --context feddemocl1 -n ${GOGS_NAMESPACE} apply -f yaml-resources/gogs/postgres.yaml"
  wait_for_deployment_ready "feddemocl1" "${GOGS_NAMESPACE}" "postgres" "0"
  run_ok_or_fail 'cat yaml-resources/gogs/gogs.yaml | sed "s/changeMe/${GOGS_ROUTE}/g" | oc --context feddemocl1 -n ${GOGS_NAMESPACE} apply -f -' "0" "1"
  wait_for_deployment_ready "feddemocl1" "${GOGS_NAMESPACE}" "gogs" "0"
  echo "Initializing Gogs User"
  GOGS_POD=$(oc --context feddemocl1 -n ${GOGS_NAMESPACE} get pod -l name=gogs -o jsonpath='{.items[*].metadata.name}')
  run_ok_or_fail 'oc --context feddemocl1 -n ${GOGS_NAMESPACE} exec ${GOGS_POD} init-gogs "demouser" "demouser" "demouser@d3m0.com"' "0" "1"
  echo "Initializing Git Demo Repository"
  GOGS_TOKEN_OUTPUT=$(curl -s -X POST -H 'Content-Type: application/json' --data '{"name":"api"}' "http://demouser:demouser@$GOGS_ROUTE/api/v1/users/demouser/tokens")
  GOGS_TOKEN=$(echo $GOGS_TOKEN_OUTPUT | ./bin/jq -r '.sha1')
  REPO_DATA='{"name": "gitops-demo", "description": "GitOps Automated Demo Repository", "readme": "Default", "auto_init": true, "private": false}'
  sleep 2
  echo "Create Git Repository using the Gogs API"
  run_ok_or_fail 'curl -s -X POST -H "Content-Type: application/json" -H "Authorization: token $GOGS_TOKEN" --data "$REPO_DATA" "http://$GOGS_ROUTE/api/v1/admin/users/demouser/repos"' "0" "1"
  sleep 2
  echo "Clone the Git Repository locally"
  rm -rf gitops-demo/ &> /dev/null
  run_ok_or_fail 'git clone "http://demouser:demouser@$GOGS_ROUTE/demouser/gitops-demo.git"' "0" "1"
  echo "Gogs setup completed"
}

load_git_content()
{
  cd gitops-demo &> /dev/null
  mkdir -p mongo/base mongo/overlays/cluster1 mongo/overlays/cluster2 mongo/overlays/cluster3 pacman/base pacman/overlays/cluster1 pacman/overlays/cluster2 pacman/overlays/cluster3 &> /dev/null
  cp -pf ../yaml-resources/mongo/base/kustomization.yaml mongo/base/kustomization.yaml &> /dev/null
  cp -pf ../yaml-resources/mongo/base/mongo-namespace-mod.yaml mongo/base/mongo-namespace.yaml &> /dev/null
  cp -pf ../yaml-resources/mongo/base/mongo-pvc.yaml mongo/base/mongo-pvc.yaml &> /dev/null
  cp -pf ../yaml-resources/mongo/base/mongo-route.yaml mongo/base/mongo-route.yaml &> /dev/null
  cp -pf ../yaml-resources/mongo/base/mongo-rs-deployment-mod.yaml mongo/base/mongo-rs-deployment.yaml &> /dev/null
  cp -pf ../yaml-resources/mongo/base/mongo-secret-mod.yaml mongo/base/mongo-secret.yaml &> /dev/null
  cp -pf ../yaml-resources/mongo/base/mongo-service.yaml mongo/base/mongo-service.yaml &> /dev/null
  cp -pf ../yaml-resources/mongo/overlays/cluster1/kustomization.yaml mongo/overlays/cluster1/kustomization.yaml &> /dev/null
  cp -pf ../yaml-resources/mongo/overlays/cluster1/mongo-route-mod.yaml mongo/overlays/cluster1/mongo-route.yaml &> /dev/null
  cp -pf ../yaml-resources/mongo/overlays/cluster2/kustomization.yaml mongo/overlays/cluster2/kustomization.yaml &> /dev/null
  cp -pf ../yaml-resources/mongo/overlays/cluster2/mongo-route-mod.yaml mongo/overlays/cluster2/mongo-route.yaml &> /dev/null
  cp -pf ../yaml-resources/mongo/overlays/cluster3/kustomization.yaml mongo/overlays/cluster3/kustomization.yaml &> /dev/null
  cp -pf ../yaml-resources/mongo/overlays/cluster3/mongo-route-mod.yaml mongo/overlays/cluster3/mongo-route.yaml &> /dev/null
  cp -pf ../yaml-resources/pacman/base/kustomization.yaml pacman/base/kustomization.yaml &> /dev/null
  cp -pf ../yaml-resources/pacman/base/pacman-namespace-mod.yaml pacman/base/pacman-namespace.yaml &> /dev/null
  cp -pf ../yaml-resources/pacman/base/pacman-cluster-role-binding-mod.yaml pacman/base/pacman-cluster-role-binding.yaml &> /dev/null
  cp -pf ../yaml-resources/pacman/base/pacman-cluster-role.yaml pacman/base/pacman-cluster-role.yaml &> /dev/null
  cp -pf ../yaml-resources/pacman/base/pacman-deployment-mod.yaml pacman/base/pacman-deployment.yaml &> /dev/null
  cp -pf ../yaml-resources/pacman/base/pacman-route-mod.yaml pacman/base/pacman-route.yaml &> /dev/null
  cp -pf ../yaml-resources/pacman/base/pacman-secret.yaml pacman/base/pacman-secret.yaml &> /dev/null
  cp -pf ../yaml-resources/pacman/base/pacman-service-account.yaml pacman/base/pacman-service-account.yaml &> /dev/null
  cp -pf ../yaml-resources/pacman/base/pacman-service.yaml pacman/base/pacman-service.yaml &> /dev/null
  cp -pf ../yaml-resources/pacman/overlays/cluster1/kustomization.yaml pacman/overlays/cluster1/kustomization.yaml &> /dev/null
  cp -pf ../yaml-resources/pacman/overlays/cluster1/pacman-deployment.yaml pacman/overlays/cluster1/pacman-deployment.yaml &> /dev/null
  cp -pf ../yaml-resources/pacman/overlays/cluster2/kustomization.yaml pacman/overlays/cluster2/kustomization.yaml &> /dev/null
  cp -pf ../yaml-resources/pacman/overlays/cluster2/pacman-deployment.yaml pacman/overlays/cluster2/pacman-deployment.yaml &> /dev/null
  cp -pf ../yaml-resources/pacman/overlays/cluster3/kustomization.yaml pacman/overlays/cluster3/kustomization.yaml &> /dev/null
  cp -pf ../yaml-resources/pacman/overlays/cluster3/pacman-deployment.yaml pacman/overlays/cluster3/pacman-deployment.yaml &> /dev/null
  git add --all &> /dev/null
  git commit -m "Loaded Pacman and MongoDB manifests" &> /dev/null
  git push origin master &> /dev/null
  cd .. &> /dev/null
}

pacman_scale()
{
  CLUSTER="$1"
  REPLICAS="$2"
  cd gitops-demo &> /dev/null
  sed -i "s/replicas: .*$/replicas: $REPLICAS/g" pacman/overlays/$CLUSTER/pacman-deployment.yaml
  git add pacman/overlays/$CLUSTER/pacman-deployment.yaml &> /dev/null
  git commit -m "Updated pacman replicas on $CLUSTER to $REPLICAS" &> /dev/null
  git push origin master &> /dev/null
  cd .. &> /dev/null
}

setup_mongo_tls()
{
  SERVICE_NAME=mongo
  NAMESPACE=${DEMO_NAMESPACE}
  ROUTE_CLUSTER1="mongo-${DEMO_NAMESPACE}.${WILDCARD_DOMAIN_CL1}"
  ROUTE_CLUSTER2="mongo-${DEMO_NAMESPACE}.${WILDCARD_DOMAIN_CL2}"
  ROUTE_CLUSTER3="mongo-${DEMO_NAMESPACE}.${WILDCARD_DOMAIN_CL3}"
  PACMAN_INGRESS=pacman-ingress.${WILDCARD_DOMAIN_CL1}
  SANS="localhost,localhost.localdomain,127.0.0.1,${ROUTE_CLUSTER1},${ROUTE_CLUSTER2},${ROUTE_CLUSTER3},${SERVICE_NAME},${SERVICE_NAME}.${NAMESPACE},${SERVICE_NAME}.${NAMESPACE}.svc.cluster.local"
  download_cfssl_tools
  cd ssl &> /dev/null
  echo "Generating CA"
  run_ok_or_fail "../bin/cfssl gencert -initca ca-csr.json | ../bin/cfssljson -bare ca" "0" "1"
  echo "Generating MongoDB Certs"
  run_ok_or_fail "../bin/cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -hostname=${SANS} -profile=kubernetes mongodb-csr.json | ../bin/cfssljson -bare mongodb" "0" "1"
  echo "Generating a PEM with MongoDB Cert Priv/Pub Key"
  cat mongodb-key.pem mongodb.pem > mongo.pem 
  echo "Crafting MongoDB OCP Secret containing certificates information"
  cp -pf ../yaml-resources/mongo/base/mongo-secret.yaml ../yaml-resources/mongo/base/mongo-secret-mod.yaml &> /dev/null
  cp -pf ../yaml-resources/mongo/base/mongo-rs-deployment.yaml ../yaml-resources/mongo/base/mongo-rs-deployment-mod.yaml &> /dev/null
  cp -pf ../yaml-resources/pacman/base/pacman-route.yaml ../yaml-resources/pacman/base/pacman-route-mod.yaml &> /dev/null
  cp -pf ../yaml-resources/pacman/base/pacman-cluster-role-binding.yaml ../yaml-resources/pacman/base/pacman-cluster-role-binding-mod.yaml &> /dev/null
  cp -pf ../yaml-resources/pacman/base/pacman-deployment.yaml ../yaml-resources/pacman/base/pacman-deployment-mod.yaml &> /dev/null
  cp -pf ../yaml-resources/mongo/overlays/cluster1/mongo-route.yaml ../yaml-resources/mongo/overlays/cluster1/mongo-route-mod.yaml &> /dev/null
  cp -pf ../yaml-resources/mongo/overlays/cluster2/mongo-route.yaml ../yaml-resources/mongo/overlays/cluster2/mongo-route-mod.yaml &> /dev/null
  cp -pf ../yaml-resources/mongo/overlays/cluster3/mongo-route.yaml ../yaml-resources/mongo/overlays/cluster3/mongo-route-mod.yaml &> /dev/null
  cp -pf ../yaml-resources/mongo/base/mongo-namespace.yaml ../yaml-resources/mongo/base/mongo-namespace-mod.yaml &> /dev/null
  cp -pf ../yaml-resources/pacman/base/pacman-namespace.yaml ../yaml-resources/pacman/base/pacman-namespace-mod.yaml &> /dev/null
  run_ok_or_fail 'sed -i "s/mongodb.pem: .*$/mongodb.pem: $(openssl base64 -A < mongo.pem)/" ../yaml-resources/mongo/base/mongo-secret-mod.yaml' "1" "1"
  run_ok_or_fail 'sed -i "s/ca.pem: .*$/ca.pem: $(openssl base64 -A < ca.pem)/" ../yaml-resources/mongo/base/mongo-secret-mod.yaml' "1" "1"
  echo "Crafting MongoDB OCP Deployment containing mongodb endpoints"
  run_ok_or_fail 'sed -i "s/primarynodehere/${ROUTE_CLUSTER1}:443/" ../yaml-resources/mongo/base/mongo-rs-deployment-mod.yaml' "0" "1"
  run_ok_or_fail 'sed -i "s/replicamembershere/${ROUTE_CLUSTER1}:443,${ROUTE_CLUSTER2}:443,${ROUTE_CLUSTER3}:443/" ../yaml-resources/mongo/base/mongo-rs-deployment-mod.yaml' "0" "1"
  echo "Crafting MongoDB OCP Routes"
  run_ok_or_fail 'sed -i "s/mongocluster1route/${ROUTE_CLUSTER1}/" ../yaml-resources/mongo/overlays/cluster1/mongo-route-mod.yaml' "0" "1"
  run_ok_or_fail 'sed -i "s/mongocluster2route/${ROUTE_CLUSTER2}/" ../yaml-resources/mongo/overlays/cluster2/mongo-route-mod.yaml' "0" "1"
  run_ok_or_fail 'sed -i "s/mongocluster3route/${ROUTE_CLUSTER3}/" ../yaml-resources/mongo/overlays/cluster3/mongo-route-mod.yaml' "0" "1"
  echo "Crafting Pacman OCP Deployment containing mongodb endpoints"
  run_ok_or_fail 'sed -i "s/pacmanhosthere/${PACMAN_INGRESS}/" ../yaml-resources/pacman/base/pacman-route-mod.yaml' "0" "1"
  run_ok_or_fail 'sed -i "s/primarymongohere/${ROUTE_CLUSTER1}/" ../yaml-resources/pacman/base/pacman-deployment-mod.yaml' "0" "1"
  run_ok_or_fail 'sed -i "s/namespace: pacmanNS/namespace: ${DEMO_NAMESPACE}/" ../yaml-resources/pacman/base/pacman-cluster-role-binding-mod.yaml' "0" "1"
  run_ok_or_fail 'sed -i "s/replicamembershere/${ROUTE_CLUSTER1},${ROUTE_CLUSTER2},${ROUTE_CLUSTER3}/" ../yaml-resources/pacman/base/pacman-deployment-mod.yaml' "0" "1"
  echo "Setting up namespaces definition for Mongo and Pacman files"
  run_ok_or_fail 'sed -i "s/mongoNS/${DEMO_NAMESPACE}/" ../yaml-resources/mongo/base/mongo-namespace-mod.yaml' "0" "1"
  run_ok_or_fail 'sed -i "s/pacmanNS/${DEMO_NAMESPACE}/" ../yaml-resources/pacman/base/pacman-namespace-mod.yaml' "0" "1"
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
      echo "No $POD_NAME pods running"
      READY=1
    else
      echo "There are $POD_NAME pods running, waiting for termination... [$WAIT/$MAX_WAIT]"
      sleep 5
      WAIT=$(expr $WAIT + 5)
    fi
    if [ $WAIT -ge $MAX_WAIT ]
    then
      echo "Timeout while waiting pod ${POD_NAME} from namespace ${POD_NAMESPACE} on cluster ${CLUSTER} to be terminated"
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
  IS_DEPLOYMENT_CONFIG="$4"
  K8S_OBJECT="deployment"
  if [ "0$IS_DEPLOYMENT_CONFIG" -eq "01" ]
  then
    K8S_OBJECT="deploymentconfig"
  fi
  echo "Checking if ${K8S_OBJECT} ${DEPLOYMENT_NAME} from namespace ${DEPLOYMENT_NAMESPACE} on cluster ${CLUSTER} is ready"

  while [ $READY -eq 0 ]
  do
    DEPLOYMENT_EXISTS=$(oc --context=${CLUSTER} -n ${DEPLOYMENT_NAMESPACE} get ${K8S_OBJECT} ${DEPLOYMENT_NAME} -o name 2>/dev/null | awk -F "/" '{print $2}')
    if [ "0${DEPLOYMENT_NAME}" == "0${DEPLOYMENT_EXISTS}" ]
    then
      READY=1
    else
      echo "Deployment still does not exists, waiting for its creation... [$WAIT/$MAX_WAIT]"
      sleep 5
      WAIT=$(expr $WAIT + 5)
    fi
    if [ $WAIT -ge $MAX_WAIT ]
    then
      echo "Timeout while waiting ${K8S_OBJECT} ${DEPLOYMENT_NAME} from namespace ${DEPLOYMENT_NAMESPACE} on cluster ${CLUSTER} to be created"
      exit 1
    fi
  done

  READY=0
  WAIT=0
  DESIRED_REPLICAS=$(oc --context=${CLUSTER} -n ${DEPLOYMENT_NAMESPACE} get ${K8S_OBJECT} ${DEPLOYMENT_NAME} -o jsonpath='{ .spec.replicas }')
  while [ $READY -eq 0 ]
  do
    CLUSTER_REPLICAS_READY=$(oc --context=${CLUSTER} -n ${DEPLOYMENT_NAMESPACE} get ${K8S_OBJECT} ${DEPLOYMENT_NAME} -o jsonpath='{ .status.readyReplicas }')
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
      echo "Timeout while waiting ${K8S_OBJECT} ${DEPLOYMENT_NAME} from namespace ${DEPLOYMENT_NAMESPACE} on cluster ${CLUSTER} to become ready"
      exit 1
    fi
  done
}

wait_for_argocd_app_deleted()
{
  READY=0
  WAIT=0
  MAX_WAIT=300
  APP_NAME="$1"
  echo "Waiting for application ${APP_NAME} to be deleted"
  
  while [ $READY -eq 0 ]
  do
    STATUS=$(./bin/argocd app list | grep -c "${APP_NAME}")
    if [ "0$STATUS" == "00" ]
    then
      echo "Application deleted successfully"
      READY=1
    else
      echo "Application is still being deleted, waiting... [$WAIT/$MAX_WAIT]"
      sleep 5
      WAIT=$(expr $WAIT + 5) 
    fi
    if [ $WAIT -ge $MAX_WAIT ]
    then
      echo "Timeout while waiting application ${APP_NAME} to be deleted"
      exit 1
    fi
  done
}

wait_for_argocd_app()
{
  READY=0
  WAIT=0
  MAX_WAIT=300
  APP_NAME="$1"
  echo "Checking if application ${APP_NAME} is ready"
  
  DESIRED_STATUS="Healthy"
  while [ $READY -eq 0 ]
  do
    STATUS=$(./bin/argocd app get ${APP_NAME} 2>/dev/null | grep "Health Status" | awk -F ":" '{print $2}' | tr -d " ")
    if [ "0$STATUS" == "0$DESIRED_STATUS" ]
    then
      echo "Application is ready"
      READY=1
    else
      echo "Application is not ready yet, waiting... [$WAIT/$MAX_WAIT]"
      sleep 5
      WAIT=$(expr $WAIT + 5) 
    fi
    if [ $WAIT -ge $MAX_WAIT ]
    then
      echo "Timeout while waiting application ${APP_NAME} to become ready"
      exit 1
    fi
  done
}

approve_installplan()
{
  READY=0
  WAIT=0
  MAX_WAIT=300
  CLUSTER="$1"
  INSTALLPLAN_NAMESPACE="$2"
  echo "Waiting installPlan to be created on namespace ${INSTALLPLAN_NAMESPACE}"
  while [ $READY -eq 0 ]
  do
    INSTALLPLAN_NAME=$(oc --context=${CLUSTER} -n ${INSTALLPLAN_NAMESPACE} get installplan -o name 2>/dev/null | awk -F "/" '{print $2}')
    if [ "$INSTALLPLAN_NAME" != "" ]
    then
      echo "InstallPlan ${INSTALLPLAN_NAME} detected. Proceeding to approve it"
      PATCH='{"spec":{"approved":true}}'
      run_ok_or_fail "oc --context=${CLUSTER} -n ${INSTALLPLAN_NAMESPACE} patch installplan ${INSTALLPLAN_NAME} --type=merge -p '${PATCH}'" "0" "1"
      echo "InstallPlan patched"
      READY=1
    else
      echo "InstallPlan still not created, waiting... [$WAIT/$MAX_WAIT]"
      sleep 5
      WAIT=$(expr $WAIT + 5)
    fi
    if [ $WAIT -ge $MAX_WAIT ]
    then
      echo "Timeout while waiting installPlan to be created on namespace ${INSTALLPLAN_NAMESPACE} on cluster ${CLUSTER}"
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
  run_ok_or_fail "./bin/argocd app delete cluster1-pacman" "0" "1" "1"
  run_ok_or_fail "./bin/argocd app delete cluster2-pacman" "0" "1" "1"
  run_ok_or_fail "./bin/argocd app delete cluster3-pacman" "0" "1" "1"
  echo "Deleting MongoDB resources"
  run_ok_or_fail "./bin/argocd app delete cluster1-mongo" "0" "1" "1"
  run_ok_or_fail "./bin/argocd app delete cluster2-mongo" "0" "1" "1"
  run_ok_or_fail "./bin/argocd app delete cluster3-mongo" "0" "1" "1"
  wait_for_argocd_app_deleted "cluster1-pacman"
  wait_for_argocd_app_deleted "cluster2-pacman"
  wait_for_argocd_app_deleted "cluster3-pacman"
  wait_for_argocd_app_deleted "cluster1-mongo"
  wait_for_argocd_app_deleted "cluster2-mongo"
  wait_for_argocd_app_deleted "cluster3-mongo"
}

haproxy_cleanup()
{
  echo "Deleting HAProxy"
  run_ok_or_fail "oc --context=feddemocl1 delete namespace ${HAPROXY_NAMESPACE}" "0" "1"
}

argocd_cleanup()
{
  echo "Deleting Argo CD"
  echo "Removing namespace from cluster"
  DELETE_NS=$(delete_annotated_namespace feddemocl1 ${ARGOCD_NAMESPACE})
  if [ "0${DELETE_NS}" == "01" ]
  then
    run_ok_or_fail "oc --context=feddemocl1 delete namespace ${ARGOCD_NAMESPACE}" "0" "1" "1"
  fi
}

gogs_cleanup()
{
  echo "Deleting Gogs"
  echo "Removing namespace from cluster"
  DELETE_NS=$(delete_annotated_namespace feddemocl1 ${GOGS_NAMESPACE})
  if [ "0${DELETE_NS}" == "01" ]
  then
    run_ok_or_fail "oc --context=feddemocl1 delete namespace ${GOGS_NAMESPACE}" "0" "1" "1"
  fi
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
  PACMAN_URL=pacman-multicluster.${WILDCARD_DOMAIN_CL1}
  run_ok_or_fail "curl -X POST http://${PACMAN_URL}/highscores -H 'Content-Type: application/x-www-form-urlencoded' -d 'name=${PLAYER_NAME}&cloud=${CLOUD_NAME}&zone=${ZONE_NAME}&host=${HOST_NAME}&score=${SCORE_POINTS}&level=${LEVEL}'" "0" "1" 
}

check_ci_scores()
{
  PACMAN_URL=pacman-multicluster.${WILDCARD_DOMAIN_CL1}
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
    REPLICASET_STATUS=$(oc --context=${CLUSTER} -n ${NAMESPACE} exec ${MONGO_POD} -- bash -c 'mongo --norc --quiet --username=admin --password=$MONGODB_ADMIN_PASSWORD --host localhost admin --tls --tlsCAFile /opt/mongo-ssl/ca.pem --eval "JSON.stringify(rs.status())"' 2> /dev/null)
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
  echo ""
  echo "MongoDB ReplicaSet Status:"
  echo "--------------------------"
  echo "Primary Member:"
  echo $REPLICASET_STATUS | ./bin/jq '.members[] | select(.state | contains(1)).name'
  echo "Secondary Members:"
  echo $REPLICASET_STATUS | ./bin/jq '.members[] | select(.state | contains(2)).name'
  echo ""
}

check_ci_replicaset()
{
  MEMBER_CLUSTER1="mongo-${DEMO_NAMESPACE}.${WILDCARD_DOMAIN_CL1}:443"
  MEMBER_CLUSTER2="mongo-${DEMO_NAMESPACE}.${WILDCARD_DOMAIN_CL2}:443"
  MEMBER_CLUSTER3="mongo-${DEMO_NAMESPACE}.${WILDCARD_DOMAIN_CL3}:443"
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
  PACMAN_URL=pacman-multicluster.${WILDCARD_DOMAIN_CL1}
  GOGS_ROUTE=gogs-demo.${WILDCARD_DOMAIN_CL1}
  echo "1. Let's start by configuring our Git repository into Argo CD."
  run_ok_or_fail "./bin/argocd repo add http://$GOGS_ROUTE/demouser/gitops-demo.git" "0" "1"
  echo "2. Now it is time to create our MongoDB Argo CD Applications so we will get a MongoDB replica running on each cluster."
  run_ok_or_fail "./bin/argocd app create --project default --name cluster1-mongo --repo http://$GOGS_ROUTE/demouser/gitops-demo.git --path mongo/overlays/cluster1 --dest-server $(./bin/argocd cluster list | grep feddemocl1 | awk '{print $1}') --dest-namespace ${DEMO_NAMESPACE} --revision master --sync-policy automated" "0" "1"
  run_ok_or_fail "./bin/argocd app create --project default --name cluster2-mongo --repo http://$GOGS_ROUTE/demouser/gitops-demo.git --path mongo/overlays/cluster2 --dest-server $(./bin/argocd cluster list | grep feddemocl2 | awk '{print $1}') --dest-namespace ${DEMO_NAMESPACE} --revision master --sync-policy automated" "0" "1"
  run_ok_or_fail "./bin/argocd app create --project default --name cluster3-mongo --repo http://$GOGS_ROUTE/demouser/gitops-demo.git --path mongo/overlays/cluster3 --dest-server $(./bin/argocd cluster list | grep feddemocl3 | awk '{print $1}') --dest-namespace ${DEMO_NAMESPACE} --revision master --sync-policy automated" "0" "1"
  wait_for_argocd_app "cluster1-mongo"
  wait_for_argocd_app "cluster2-mongo"
  wait_for_argocd_app "cluster3-mongo"
  echo "3. At this point we have the "${DEMO_NAMESPACE}" namespace across three different clusters (Cluster1, Cluster2 and Cluster3)." 
  run_ok_or_fail 'for cluster in feddemocl1 feddemocl2 feddemocl3;do echo **Cluster ${cluster}**;oc --context=$cluster get namespaces ${DEMO_NAMESPACE};done' "1" "1"
  echo "4. Two Secrets have been created across the clusters, the secrets include the certificates and user/password details for connecting to MongoDB."
  wait_for_input
  run_ok_or_fail 'for cluster in feddemocl1 feddemocl2 feddemocl3;do echo **Cluster ${cluster}**;oc --context=$cluster -n ${DEMO_NAMESPACE} get secrets | grep mongodb;done' "1" "1"
  echo "5. A service for MongoDB has been created on each cluster"
  wait_for_input
  run_ok_or_fail 'for cluster in feddemocl1 feddemocl2 feddemocl3;do echo **Cluster ${cluster}**;oc --context=$cluster -n ${DEMO_NAMESPACE} get services --selector="name=mongo";done' "1" "1" 
  echo "6. Our MongoDB deployment needs a volume in order to store the MongoDB data, so a PVC has been created on each cluster"
  wait_for_input
  run_ok_or_fail 'for cluster in feddemocl1 feddemocl2 feddemocl3;do echo **Cluster ${cluster}**;oc --context=$cluster -n ${DEMO_NAMESPACE} get pvc mongo;done' "1" "1"
  echo "7. A MongoDB pod is deployed on each cluster, we will configure the ReplicaSet in the nexts steps"
  wait_for_input
  run_ok_or_fail 'for cluster in feddemocl1 feddemocl2 feddemocl3;do echo **Cluster ${cluster}**;oc --context=$cluster -n ${DEMO_NAMESPACE} get pods --selector="name=mongo";done' "1" "1"
  echo "8. Finally, a route is created in order to get external traffic to our MongoDB pods on each cluster, these routes will be passthrough as we need MongoDB to handle the certs and the connection to remain TLS rather than HTTPS."
  wait_for_input
  run_ok_or_fail 'for cluster in feddemocl1 feddemocl2 feddemocl3;do echo **Cluster ${cluster}**;oc --context=$cluster -n ${DEMO_NAMESPACE} get route mongo;done' "1" "1"
  echo "9. Next we are going to configure the MongoDB ReplicaSet, this procedure has been automated and the only thing you need to do is label the primary pod, in this case the one running on Cluster1."
  wait_for_input
  wait_for_deployment_ready "feddemocl1" "${DEMO_NAMESPACE}" "mongo" "0"
  wait_for_deployment_ready "feddemocl2" "${DEMO_NAMESPACE}" "mongo" "0"
  wait_for_deployment_ready "feddemocl3" "${DEMO_NAMESPACE}" "mongo" "0"
  MONGO_POD=$(oc --context=feddemocl1 -n ${DEMO_NAMESPACE} get pod --selector="name=mongo" --output=jsonpath='{.items..metadata.name}')
  run_ok_or_fail "oc --context=feddemocl1 -n ${DEMO_NAMESPACE} label pod $MONGO_POD replicaset=primary" "0" "1"
  wait_for_mongodb_replicaset "feddemocl1" "${DEMO_NAMESPACE}" "3"
  echo "10. Now it is time to create our Pacman Argo CD Applications so we will get a Pacman replica running on each cluster."
  wait_for_input
  run_ok_or_fail "./bin/argocd app create --project default --name cluster1-pacman --repo http://$GOGS_ROUTE/demouser/gitops-demo.git --path pacman/overlays/cluster1 --dest-server $(./bin/argocd cluster list | grep feddemocl1 | awk '{print $1}') --dest-namespace ${DEMO_NAMESPACE} --revision master --sync-policy automated" "0" "1"
  run_ok_or_fail "./bin/argocd app create --project default --name cluster2-pacman --repo http://$GOGS_ROUTE/demouser/gitops-demo.git --path pacman/overlays/cluster2 --dest-server $(./bin/argocd cluster list | grep feddemocl2 | awk '{print $1}') --dest-namespace ${DEMO_NAMESPACE} --revision master --sync-policy automated" "0" "1"
  run_ok_or_fail "./bin/argocd app create --project default --name cluster3-pacman --repo http://$GOGS_ROUTE/demouser/gitops-demo.git --path pacman/overlays/cluster3 --dest-server $(./bin/argocd cluster list | grep feddemocl3 | awk '{print $1}') --dest-namespace ${DEMO_NAMESPACE} --revision master --sync-policy automated" "0" "1"
  wait_for_argocd_app "cluster1-pacman"
  wait_for_argocd_app "cluster2-pacman"
  wait_for_argocd_app "cluster3-pacman"
  echo "11. As we did before, Pacman needs some services to be created."
  wait_for_input
  run_ok_or_fail 'for cluster in feddemocl1 feddemocl2 feddemocl3;do echo **Cluster ${cluster}**;oc --context=$cluster -n ${DEMO_NAMESPACE} get services --selector="name=pacman";done' "1" "1" 
  echo "12. A Route is needed as well, we have created one Route that points to the HAProxy Load Balancer on each cluster."
  wait_for_input
  run_ok_or_fail 'for cluster in feddemocl1 feddemocl2 feddemocl3;do echo **Cluster ${cluster}**;oc --context=$cluster -n ${DEMO_NAMESPACE} get route pacman;done' "1" "1"
  echo "13. A ServiceAccount is created to be used by the pacman application."
  wait_for_input
  run_ok_or_fail 'for cluster in feddemocl1 feddemocl2 feddemocl3;do echo **Cluster ${cluster}**;oc --context=$cluster -n ${DEMO_NAMESPACE} get serviceaccount pacman;done' "1" "1"
  echo "14. We need a ClusterRole to allow for the pacman application to interact with the Kubernetes API."
  wait_for_input
  run_ok_or_fail 'for cluster in feddemocl1 feddemocl2 feddemocl3;do echo **Cluster ${cluster}**;oc --context=$cluster get clusterrole pacman;done' "1" "1"
  echo "15. With the ClusterRole in place we need to bind the ServiceAccount with the ClusterRole, we are using a ClusterRoleBinding for that."
  wait_for_input
  run_ok_or_fail 'for cluster in feddemocl1 feddemocl2 feddemocl3;do echo **Cluster ${cluster}**;oc --context=$cluster get clusterrolebinding pacman;done' "1" "1"
  echo "16. As with MongoDB, we have a Pacman replica on each cluster."
  wait_for_input
  wait_for_deployment_ready "feddemocl1" "${DEMO_NAMESPACE}" "pacman" "0"
  wait_for_deployment_ready "feddemocl2" "${DEMO_NAMESPACE}" "pacman" "0"
  wait_for_deployment_ready "feddemocl3" "${DEMO_NAMESPACE}" "pacman" "0"
  run_ok_or_fail 'for cluster in feddemocl1 feddemocl2 feddemocl3;do echo **Cluster ${cluster}**;oc --context=$cluster -n ${DEMO_NAMESPACE} get pods --selector="name=pacman";done' "1" "1"
  echo "17. Go play Pacman and save some highscores. http://${PACMAN_URL} (Note: Pretend you're bad at Pacman)."
  wait_for_input
  if [ $CI_MODE -eq 1 ]
  then
    simulate_pacman_play "Nathan" "AWS" "us-east-1a" "padman-pod-1" "288" "1"
    sleep 3
    simulate_pacman_play "Joel" "AWS" "us-west-1a" "padman-pod-2" "196" "1"
  fi
  echo "18. Well, everything should be working fine. Let's create some chaos, what will happen if primary mongo pod gets deleted?"
  wait_for_input
  run_ok_or_fail "./bin/argocd app delete cluster1-mongo" "0" "1"
  wait_for_pod_not_running "feddemocl1" "${DEMO_NAMESPACE}" "mongo"
  run_ok_or_fail "oc --context=feddemocl1 -n ${DEMO_NAMESPACE} get pods --selector='name=mongo'" "1" "1"
  echo "19. Let's continue playing and see if we can save highscores. http://${PACMAN_URL}. (Note: Saving the high score could take longer than usual)."
  wait_for_input
  if [ $CI_MODE -eq 1 ]
  then
    simulate_pacman_play "Ash" "GCP" "us-east-1b" "padman-pod-1" "150" "1"    
    sleep 3
    simulate_pacman_play "Gary" "GCP" "us-west-1b" "padman-pod-2" "149" "1"
  fi
  echo "20. Well, our Pacman application is not that famous, let's scale it so it only runs on one of our clusters."
  pacman_scale "cluster1" "0"
  pacman_scale "cluster3" "0"
  run_ok_or_fail "./bin/argocd app sync cluster1-pacman" "0" "1"
  run_ok_or_fail "./bin/argocd app sync cluster3-pacman" "0" "1"
  sleep 3
  run_ok_or_fail 'for cluster in feddemocl1 feddemocl2 feddemocl3;do echo **Cluster ${cluster}**;oc --context=$cluster -n ${DEMO_NAMESPACE} get pods --selector="name=pacman";done' "1" "1"
  echo "21. Our engineers have been working hard during the weekend and the cluster where the primary mongo pod was deployed came back to life."
  wait_for_input
  run_ok_or_fail "./bin/argocd app create --project default --name cluster1-mongo --repo http://$GOGS_ROUTE/demouser/gitops-demo.git --path mongo/overlays/cluster1 --dest-server $(./bin/argocd cluster list | grep feddemocl1 | awk '{print $1}') --dest-namespace ${DEMO_NAMESPACE} --revision master --sync-policy automated" "0" "1"
  sleep 5
  run_ok_or_fail "oc --context=feddemocl1 -n ${DEMO_NAMESPACE} get pods --selector='name=mongo'" "1" "1"
  echo "22. Our Pacman application has become trendy among teenagers, they don't want to play Fortnite anymore. We need to scale!!"
  wait_for_input
  pacman_scale "cluster1" "3"
  pacman_scale "cluster3" "4"
  run_ok_or_fail "./bin/argocd app sync cluster1-pacman" "0" "1"
  run_ok_or_fail "./bin/argocd app sync cluster3-pacman" "0" "1"
  wait_for_deployment_ready "feddemocl1" "${DEMO_NAMESPACE}" "pacman" "0"
  wait_for_deployment_ready "feddemocl2" "${DEMO_NAMESPACE}" "pacman" "0"
  wait_for_deployment_ready "feddemocl3" "${DEMO_NAMESPACE}" "pacman" "0"
  run_ok_or_fail 'for cluster in feddemocl1 feddemocl2 feddemocl3;do echo **Cluster ${cluster}**;oc --context=$cluster -n ${DEMO_NAMESPACE} get pods --selector="name=pacman";done' "1" "1"
  echo "23. Bonus track: We should see our MongoDB Replica being restored."
  wait_for_deployment_ready "feddemocl1" "${DEMO_NAMESPACE}" "mongo" "0"
  wait_for_mongodb_replicaset "feddemocl1" "${DEMO_NAMESPACE}" "3"
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
  RUN_SETUP_ARGOCD=0
  RUN_SETUP_GOGS=0
  RUN_SETUP_HAPROXY=0
  RUN_SETUP_MONGO=0
  RUN_GIT_LOAD=0
  RUN_DEMO_ONLY=0
  for STEP_TO_CHECK in $(echo $STEPS_TO_RUN | sed "s/,/ /g")
  do
    if [ "$STEP_TO_CHECK" == "context-creation" ]
    then
      RUN_CONTEXT_CREATION=1 
    elif [ "$STEP_TO_CHECK" == "setup-argocd" ]
    then
      RUN_CONTEXT_CREATION=1
      RUN_SETUP_ARGOCD=1
    elif [ "$STEP_TO_CHECK" == "setup-gogs" ]
    then
      RUN_CONTEXT_CREATION=1
      RUN_SETUP_GOGS=1
    elif [ "$STEP_TO_CHECK" == "setup-haproxy" ]
    then
      RUN_CONTEXT_CREATION=1
      RUN_SETUP_HAPROXY=1
    elif [ "$STEP_TO_CHECK" == "load-git-content" ]
    then
      RUN_CONTEXT_CREATION=1
      RUN_SETUP_MONGO=1
      RUN_GIT_LOAD=1
    elif [ "$STEP_TO_CHECK" == "demo-only" ]
    then
      RUN_CONTEXT_CREATION=1
      RUN_DEMO_ONLY=1
    elif [ "$STEP_TO_CHECK" == "all" ]
    then
      RUN_CONTEXT_CREATION=1
      RUN_SETUP_ARGOCD=1
      RUN_SETUP_GOGS=1
      RUN_SETUP_HAPROXY=1
      RUN_SETUP_MONGO=1
      RUN_GIT_LOAD=1
      RUN_DEMO_ONLY=1
      break
    else
      echo "Invalid step $STEP_TO_CHECK, valid steps: [context-creation|setup-argocd|setup-gogs|setup-haproxy|load-git-content|demo-only]"
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
      echo "We are going to get the cluster wildcard domains"
      get_clusters_wilcard_domain
    fi
    if [ $RUN_SETUP_ARGOCD -eq 1 ]
    then
      echo -ne "\n\n\nNow it's time to deploy Argo CD\n"
      setup_argocd
    fi
    if [ $RUN_SETUP_GOGS -eq 1 ]
    then
      echo -ne "\n\n\nA Gogs git server will be deployed in order to provide a single source of thruth\n"
      setup_gogs
    fi
    if [ $RUN_SETUP_HAPROXY -eq 1 ]
    then
      echo -ne "\n\n\nAn HAProxy LB will be deployed in order to provide GlobalIngress for Pacman"
      setup_haproxy
    fi
    if [ $RUN_SETUP_MONGO -eq 1 ]
    then
      echo -ne "\n\n\nMongoDB replicas will communicate with each other using TLS, so we are going to create the required certificates\n"
      setup_mongo_tls
    fi
    if [ $RUN_GIT_LOAD -eq 1 ]
    then
      echo -ne "\n\n\nOur application manifests will be loaded into Git repository\n"
      load_git_content
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
        argocd_cleanup
        gogs_cleanup
        haproxy_cleanup
      fi
      if [[ "$MODE" == "demo-cleanup" || "$MODE" == "full-cleanup" ]]
      then
        echo "Cleanup completed"
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
