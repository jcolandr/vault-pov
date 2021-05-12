
# set tenant ID from azure subscription
TENANT_ID=<Tenant ID>

#new app registration called demo to get client_id
CLIENT_ID=<Client ID>

# from new client secret under "client secrets" 
CLIENT_SECRET=<Client secret>

# from subscriptions resource copy subscription id
SUBSCRIPTION_ID=<Subscription ID>

# create resource group jdc-vault

# enable and configure the azure secretes engine
 
vault secrets enable azure

vault write azure/config \
        subscription_id=$SUBSCRIPTION_ID  \
        client_id=$CLIENT_ID \
        client_secret=$CLIENT_SECRET \
        tenant_id=$TENANT_ID

vault write azure/roles/jdc-demo ttl=5m azure_roles=-<<EOF
    [
      {
        "role_name": "Contributor",
        "scope": "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/jdc-vault"
      }
    ]
EOF

vault read azure/creds/jdc-demo

