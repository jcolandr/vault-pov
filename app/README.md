set kubectl from terraform output of aks cluster

    az aks get-credentials --resource-group $(terraform output -raw resource_group_name) --name $(terraform output -raw kubernetes_cluster_name)

creat kv-v2 secrets engine and add sample secrets

    vault secrets enable -path secret kv-v2
    vault kv put secret/app1/config username="demo" password="IT_WORKED"

enable the kubernetes auth method at default path /auth/kubernetes

    vault auth enable kubernetes

install agent injector service via helm 

    helm repo add hashicorp https://helm.releases.hashicorp.com
    helm install vault hashicorp/vault \
        --set "injector.externalVaultAddr=$VAULT_ADDR" \
        --set "csi.enabled=true" 
    
for openshift add this

    --set "global.openshift=true"

determine vault service account JWT token

    VAULT_HELM_SECRET_NAME=$(kubectl get secrets --output=json | jq -r '.items[].metadata | select(.name|startswith("vault-token-")).name')
    
check vaulue
    
    kubectl describe secret $VAULT_HELM_SECRET_NAME

set env variables for kubernetes auth method config

    TOKEN_REVIEW_JWT=$(kubectl get secret $VAULT_HELM_SECRET_NAME --output='go-template={{ .data.token }}' | base64 --decode)
    KUBE_CA_CERT=$(kubectl config view --raw --minify --flatten --output='jsonpath={.clusters[].cluster.certificate-authority-data}' | base64 --decode)
    KUBE_HOST=$(kubectl config view --raw --minify --flatten --output='jsonpath={.clusters[].cluster.server}')
    KUBE_ISSUER=${KUBE_HOST%%:443} 

configure kubernetes auth method

    vault write auth/kubernetes/config \
            issuer=""$KUBE_ISSUER"" \
            token_reviewer_jwt="$TOKEN_REVIEW_JWT" \
            kubernetes_host="$KUBE_HOST" \
            kubernetes_ca_cert="$KUBE_CA_CERT" \
            disable_iss_validation="true"

create acl policy to allow accress to secret

    vault policy write app1 - <<EOF
    path "secret/data/app1/config" {
    capabilities = ["read"]
    }
    EOF

create the role for app1

    vault write auth/kubernetes/role/app1 \
            bound_service_account_names=app1 \
            bound_service_account_namespaces=default \
            policies=app1 \
            ttl=24h

deploy app

    kubectl apply -f service-account-app1.yml
    kubectl apply -f file-deployment.yml

check that the rendered secret is found within the pod at /vault/secrets/app1-config.txt

    kubectl exec \
        $(kubectl get pod -l app=app1 -o jsonpath="{.items[0].metadata.name}") \
        --container app1 -- cat /vault/secrets/app1-config.txt ; echo

# env variable example

create app2 vault role

    vault write auth/kubernetes/role/app2 \
            bound_service_account_names=app2 \
            bound_service_account_namespaces=default \
            policies=app1 \
            ttl=24h

deploy app2

    kubectl apply -f service-account-app2.yml
    kubectl apply -f env-deployment.yml

`env` was executed by container init script and printed to logs. this command views the container log to see that the environment variable was set.

    kubectl logs $(kubectl get pod -l app=app2 -o jsonpath="{.items[0].metadata.name}") app2


# CSI

reinstall the vault helm chart or do a `helm upgrade` to a previous install

    helm install vault-csi hashicorp/vault \
        --set "csi.enabled=true" \
        --set "injector.enabled=false" \
        --set "server.enabled=false" 

the vault csi plugin relies on the secrets store csi driver install that with helm with default configuration

    helm repo add secrets-store-csi-driver https://raw.githubusercontent.com/kubernetes-sigs/secrets-store-csi-driver/master/charts
    helm install csi secrets-store-csi-driver/secrets-store-csi-driver

create vault role in kubernetes auth method for CSI app

    vault write auth/kubernetes/role/csi-app \
        bound_service_account_names=csi \
        bound_service_account_namespaces=default \
        policies=app1 \
        ttl=20m


apply the secret provider class

    kubectl apply -f spc-vault-database.yml
    kubectl describe SecretProviderClass vault-database

deploy the service account app3 to use the csi driver

    kubectl apply -f service-account-csi.yml
    kubectl apply -f csi-deployment.yml

display the password secret written to the file system at `/mnt/secrets-store/db-password` and vierw the environment variable that was sourced via the csi mounted volume

    kubectl exec \
        $(kubectl get pod -l app=app3 -o jsonpath="{.items[0].metadata.name}") \
        --container app3 -- cat /mnt/secrets-store/db-password ; echo

    kubectl exec \
        $(kubectl get pod -l app=app3 -o jsonpath="{.items[0].metadata.name}") \
        --container app3 -- printenv


# Simple App Retriving Dynamic Postgres Secrets

### Deploy App

```
$ kubectl apply -f app-db.yaml
```

### Need to create this ro role
```
$ DB_POD=$(kubectl get pod -l app=db -n vault-demo -o jsonpath="{.items[0].metadata.name}")
$ kubectl exec -it $DB_POD -n vault-demo -- psql -U postgres -d postgres -p 5432
```

### Create a ro user
```
CREATE ROLE ro NOINHERIT;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO "ro";
\q
```
### (Optional) Create Vault specific Role
```
CREATE ROLE "vault" WITH LOGIN PASSWORD 'mypassword';
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO "vault";
```

### DB Creds
```
export POSTGRES_USER=postgres
export POSTGRES_PASSWORD=postgres
export SERVICE_IP=$(kubectl get svc --namespace vault-demo db -o jsonpath='{.spec.clusterIP}')
```
### Enabling Database Secret Engine

```
vault secrets enable -path db database
```

### DB Config
```
vault write db/config/postgres \
     plugin_name=postgresql-database-plugin \
     connection_url="postgresql://{{username}}:{{password}}@$SERVICE_IP:5432/postgres?sslmode=disable" \
     allowed_roles=readonly \
     username="$POSTGRES_USER" \
     password="$POSTGRES_PASSWORD"
```

### (Optional) Rotating Vault Root PW
```
vault write -force db/rotate-root/postgres
```

### Vault DB Role
```
vault write db/roles/readonly \
      db_name=postgres \
      creation_statements=@readonly.sql \
      default_ttl=2m \
      max_ttl=2m
```

### Policy to allow app to access path

```
vault policy write app - <<EOF
path "db/creds/readonly" {
    capabilities = ["read"]
}
EOF
```

### Aligning k8s role to policy

```
vault write auth/kubernetes/role/app \
        bound_service_account_names=demo-sa \
        bound_service_account_namespaces=vault-demo \
        policies=app \
        ttl=24h

# Show Secret
kubectl exec \
    $(kubectl get pod -l app=app -n vault-demo -o jsonpath="{.items[0].metadata.name}") \
    --container app -n vault-demo -- cat /vault/secrets/app-config.txt ; echo

# Check DB
$ DB_POD=$(kubectl get pod -l app=db -n vault-demo -o jsonpath="{.items[0].metadata.name}")
$ kubectl exec -it $DB_POD -n vault-demo -- psql -U postgres -d postgres -p 5432

SELECT usename, valuntil FROM pg_user;
```

### (Optional) Revoking Lease 

```
vault lease revoke -force -prefix lease_id=database/creds/readonly
```

### Uninstalling


```
# Disable db secret engine mount first..

$ vault secrets disable db  

# Delete deployments

$ kubectl delete -f app-db.yaml                                           
namespace "vault-demo" deleted
serviceaccount "demo-sa" deleted
deployment.apps "app" deleted
deployment.apps "db" deleted
service "db" deleted
configmap "postgres-configuration" deleted
```