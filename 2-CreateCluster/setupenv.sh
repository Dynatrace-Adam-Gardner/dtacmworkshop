#!/bin/bash


export API_TOKEN=$(cat ../1-Credentials/creds.json | jq -r '.dynatraceApiToken')
export PAAS_TOKEN=$(cat ../1-Credentials/creds.json | jq -r '.dynatracePaaSToken')
export TENANTID=$(cat ../1-Credentials/creds.json | jq -r '.dynatraceTenantID')
export ENVIRONMENTID=$(cat ../1-Credentials/creds.json | jq -r '.dynatraceEnvironmentID')


if hash gcloud 2>/dev/null; then
    echo "Google Cloud"
    export CLOUD_PROVIDER=GKE
elif hash az 2>/dev/null; then
    echo "Azure Cloud"
    export CLOUD_PROVIDER=AKS
else
    echo "No supported Cloud Provider (GCP or AKS) detected."
    exit 1;
fi

echo "Creating $CLOUD_PROVIDER Cluster with the following credentials: "
echo "API_TOKEN = $API_TOKEN"
echo "PAAS_TOKEN = $PAAS_TOKEN"
echo "TENANTID = $TENANTID"
echo "ENVIRONMENTID = $ENVIRONMENTID"
echo "Cloud Provider $CLOUD_PROVIDER"

echo ""
read -p "Is this all correct? (y/n) : " -n 1 -r
echo ""

usage()
{
    echo 'Usage : ./setupenv.sh API_TOKEN PAAS_TOKEN TENANTID ENVIRONMENTID (optional if a SaaS deployment)'
    exit
}

deployGKE()
{
    echo "Creating GKE Cluster..."
    
    gcloud container clusters create acmworkshop --zone=us-central1-a --no-enable-basic-auth --machine-type "n1-standard-8" --image-type "UBUNTU" --disk-type "pd-standard" --disk-size "100" --metadata disable-legacy-endpoints=true --scopes "https://www.googleapis.com/auth/devstorage.read_only","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring","https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly","https://www.googleapis.com/auth/trace.append" --num-nodes "1" --enable-stackdriver-kubernetes --no-enable-ip-alias --network "projects/$PROJECT/global/networks/default" --subnetwork "projects/$PROJECT/regions/$REGION/subnetworks/default" --addons HorizontalPodAutoscaling,HttpLoadBalancing --no-enable-autoupgrade

    kubectl create clusterrolebinding cluster-admin-binding --clusterrole=cluster-admin --user=$(gcloud config get-value account)
}

deployAKS()
{
    echo "Creating AKS Cluster..."
    export AKS_RESOURCE_GROUP=ACM
    export AKS_CLUSTER_NAME=acmworkshop

    az group create --name $AKS_RESOURCE_GROUP --location centralus
    az aks create --resource-group $AKS_RESOURCE_GROUP --name $AKS_CLUSTER_NAME --node-count 1 --node-vm-size Standard_B4ms --generate-ssh-keys

    az aks get-credentials --resource-group $AKS_RESOURCE_GROUP --name $AKS_CLUSTER_NAME
}


if [[ $REPLY =~ ^[Yy]$ ]]; then
    case $CLOUD_PROVIDER in
        GKE)
        deployGKE
        ;;
        AKS)
        deployAKS
        ;;
        *)
        echo "No supported Cloud Provider (GCP or AKS) detected."
        exit 1
        ;;
    esac
else
    exit 1
fi


echo "Cluster created"

echo "Deploying OneAgent Operator"

../utils/deploy-dt-operator.sh

echo "Waiting for OneAgent to startup..."
sleep 120

echo "Deploying SockShop Application"
../utils/deploy-sockshop.sh

sleep 120

echo "Start Production Load"
nohup ../utils/cartsLoadTest.sh &

echo "Deployment Complete"
