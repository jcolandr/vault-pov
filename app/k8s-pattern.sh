#set kubectl from terraform output of aks cluster
az aks get-credentials --resource-group $(terraform output -raw resource_group_name) --name $(terraform output -raw kubernetes_cluster_name)

vault secrets enable -path secret kv-v2
vault kv put secret/app1/config username="demo" password="IT_WORKED"

# enable the kubernetes auth method at default path /auth/kubernetes
vault auth enable kubernetes

# install agent injector service via helm 
helm repo add hashicorp https://helm.releases.hashicorp.com
helm install vault hashicorp/vault \
    --set "injector.externalVaultAddr=$VAULT_ADDR" \
    --set "csi.enabled=true" \
    --set "global.openshift=true"


# determine vault service account JWT token
VAULT_HELM_SECRET_NAME=$(kubectl get secrets --output=json | jq -r '.items[].metadata | select(.name|startswith("vault-token-")).name')
kubectl describe secret $VAULT_HELM_SECRET_NAME

TOKEN_REVIEW_JWT=$(kubectl get secret $VAULT_HELM_SECRET_NAME --output='go-template={{ .data.token }}' | base64 --decode)
KUBE_CA_CERT=$(kubectl config view --raw --minify --flatten --output='jsonpath={.clusters[].cluster.certificate-authority-data}' | base64 --decode)
KUBE_HOST=$(kubectl config view --raw --minify --flatten --output='jsonpath={.clusters[].cluster.server}')
KUBE_ISSUER=${KUBE_HOST%%:443} 

# configure kubernetes auth method
vault write auth/kubernetes/config \
        issuer=""$KUBE_ISSUER"" \
        token_reviewer_jwt="$TOKEN_REVIEW_JWT" \
        kubernetes_host="$KUBE_HOST" \
        kubernetes_ca_cert="$KUBE_CA_CERT" \
        disable_iss_validation="true"

# create acl policy to allow accress to secret
vault policy write app1 - <<EOF
path "secret/data/app1/config" {
  capabilities = ["read"]
}
EOF

# create the role for app1
vault write auth/kubernetes/role/app1 \
        bound_service_account_names=app1 \
        bound_service_account_namespaces=default \
        policies=app1 \
        ttl=24h

# deploy app
kubectl apply -f service-account-app1.yml
kubectl apply -f file-deployment.yml

kubectl exec \
    $(kubectl get pod -l app=app1 -o jsonpath="{.items[0].metadata.name}") \
    --container app1 -- cat /vault/secrets/app1-config.txt ; echo

# kubectl exec \
#     $(kubectl get pod -l app=app1 -o jsonpath="{.items[0].metadata.name}") \
#     --container vault-agent-init -- cat /home/vault/config.json ; echo


######### env variable example

# create app2 vault role
vault write auth/kubernetes/role/app2 \
        bound_service_account_names=app2 \
        bound_service_account_namespaces=default \
        policies=app1 \
        ttl=24h

# deploy app2
kubectl apply -f service-account-app2.yml
kubectl apply -f env-deployment.yml


# kubectl exec -it $(kubectl get pod -l app=app2 -o jsonpath="{.items[0].metadata.name}") --container app2 -- /bin/sh

# 'env' was executed by container init script and printed to logs. this command views the container log to see that the environment variable was set.
kubectl logs $(kubectl get pod -l app=app2 -o jsonpath="{.items[0].metadata.name}") app2


############ CSI ################

helm install vault-csi hashicorp/vault \
    --set "csi.enabled=true" \
    --set "injector.enabled=false" \
    --set "server.enabled=false" 

helm repo add secrets-store-csi-driver https://raw.githubusercontent.com/kubernetes-sigs/secrets-store-csi-driver/master/charts
helm install csi secrets-store-csi-driver/secrets-store-csi-driver

#create vault role in kubernetes auth method for CSI app
vault write auth/kubernetes/role/csi-app \
    bound_service_account_names=csi \
    bound_service_account_namespaces=default \
    policies=app1 \
    ttl=20m


# apply the secret provider class
kubectl apply -f spc-vault-database.yml
kubectl describe SecretProviderClass vault-database

# deploy the service account app3 to use the csi driver
kubectl apply -f service-account-csi.yml
kubectl apply -f csi-deployment.yml

#display the password secret written to the file system at /mnt/secrets-store/db-password
kubectl exec \
    $(kubectl get pod -l app=app3 -o jsonpath="{.items[0].metadata.name}") \
    --container app3 -- cat /mnt/secrets-store/db-password ; echo

kubectl exec \
    $(kubectl get pod -l app=app3 -o jsonpath="{.items[0].metadata.name}") \
    --container app3 -- printenv


# dynamic postgres credential example

# create the role for app1
vault write auth/kubernetes/role/app4 \
        bound_service_account_names=app4 \
        bound_service_account_namespaces=default \
        policies=app1 \
        ttl=24h

kubectl apply -f service-account-app4.yml
kubectl apply -f dyn-file-deployment.yml 

kubectl exec \
    $(kubectl get pod -l app=app4 -o jsonpath="{.items[0].metadata.name}") \
    --container app4 -- cat /vault/secrets/app4-config.txt ; echo

