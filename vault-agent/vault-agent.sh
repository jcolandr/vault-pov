#!/bin/bash

#ip
#local_ipv4=$(curl -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/privateIpAddress?api-version=2017-08-01&format=text")
#public ip
local_ipv4=$(curl -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/publicIpAddress?api-version=2017-08-01&format=text")

#Vault Server Address
VAULT_IP=<ip>

#sudo yum -y update
sudo yum -y install unzip

#INSTALL VAULT Binary
VAULT_ZIP="https://releases.hashicorp.com/vault/1.7.1+ent/vault_1.7.1+ent_linux_amd64.zip"
#Download vault binary
curl -o /tmp/vault.zip ${VAULT_ZIP}
#add vault user
sudo useradd --system --home /home/vault --shell /bin/false vault

#put vault in path and create systemd files and server config file
sudo unzip -o /tmp/vault.zip -d /usr/local/bin/
sudo chown root:root /usr/local/bin/vault
mkdir -R /home/vault
sudo touch /home/vault/vault-agent.hcl
sudo chown -R vault:vault /etc/vault.d
sudo chmod 0775 /home/vault/vault-agent.hcl


sudo tee -a /etc/environment <<EOF
export VAULT_ADDR="http://${VAULT_IP}:8200"
export VAULT_SKIP_VERIFY=true
EOF

source /etc/environment

#Create template file
touch /home/vault/secret.tmpl

cat << EOF > /home/vault/secret.tmpl
{{ with secret "secret/data/customers/acme" }}
Organization: {{ .Data.data.organization }}
ID: {{ .Data.data.customer_id }}
Contact: {{ .Data.data.contact_email }}
{{ end }}
EOF

#create data.json
touch /home/vault/data.json

cat << EOF > /home/vault/data.json
{
  "organization": "ACME Inc.",
  "customer_id": "ABXX2398YZPIE7391",
  "region": "US-West",
  "zip_code": "94105",
  "type": "premium",
  "contact_email": "james@acme.com",
  "status": "active"
}
EOF

##--------------------------------------------------------------------
## Shortcut script
##--------------------------------------------------------------------
cat << EOF > /home/vault/vault-agent.hcl
exit_after_auth = true
pid_file = "./pidfile"

auto_auth {
   method "approle" {
       config = {
           role_id_file_path   = "/home/vault/agent-role-id"
           secret_id_file_path = "/home/vault/agent-secret-id"
       }
   }

   sink "file" {
       config = {
           path = "/home/vault/vault-token-via-agent"
       }
   }
}

vault {
   address = "http://${VAULT_IP}:8200"
}

template {
  source      = "/home/vault/secret.tmpl"
  destination = "/home/vault/rendered_secret.txt"
}
EOF


