#!/bin/bash

vault secrets enable -path=secret kv-v2
vault kv put secret/customers/acme @/home/ubuntu/data.json

echo "path \"secret/data/*\" {
    capabilities = [\"read\"]
}
path \"auth/token/*\" {
    capabilities = [\"create\", \"update\"]
}" | vault policy write agent-demo-secret-pol -

vault auth enable approle

vault write auth/approle/role/agent-demo-role policies="agent-demo-secret-pol" secret_id_ttl=90m token_num_uses=10 token_ttl=60m token_max_ttl=120m secret_id_num_uses=20

vault read auth/approle/role/agent-demo-role/role-id -format=json | jq -r '.data.role_id' > /home/vault/agent-role-id 

vault write -f auth/approle/role/agent-demo-role/secret-id -format=json | jq -r '.data.secret_id' > /home/vault/agent-secret-id 

