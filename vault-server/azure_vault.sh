#!/bin/bash

#ip
#local_ipv4=$(curl -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/privateIpAddress?api-version=2017-08-01&format=text")
#public ip
local_ipv4=$(curl -H Metadata:true --noproxy "*" "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/publicIpAddress?api-version=2017-08-01&format=text")

#sudo yum -y update
sudo yum -y install unzip

#INSTALL VAULT
VAULT_ZIP="https://releases.hashicorp.com/vault/1.7.1+ent/vault_1.7.1+ent_linux_amd64.zip"
#Download vault binary
curl -o /tmp/vault.zip ${VAULT_ZIP}
#add vault user
sudo useradd --system --home /etc/vault.d --shell /bin/false vault

#put vault in path and create systemd files and server config file
sudo unzip -o /tmp/vault.zip -d /usr/local/bin/
sudo chown root:root /usr/local/bin/vault
sudo mkdir -p /etc/vault.d
sudo touch /etc/vault.d/vault.hcl
sudo chown -R vault:vault /etc/vault.d
sudo chmod 640 /etc/vault.d/vault.hcl

#create raft storage directory
sudo mkdir -p /opt/vault/raft
sudo chown -R vault:vault /opt/vault/raft

#vault server config
sudo cat <<EOF> /etc/vault.d/vault.hcl
ui = true
#Storage
storage "raft" {
  path = "/opt/vault/raft"
  node_id = "vault-server-0"
}
# HTTP listener
listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_disable   = "true"
}

api_addr     = "http://${local_ipv4}:8200"
#api_addr     = "http://127.0.0.1:8200"
cluster_addr = "http://${local_ipv4}:8201"
#cluster_addr = "http://172.0.0.1:8201"
EOF

#configure systemd
sudo touch /etc/systemd/system/vault.service
sudo cat <<'EOF'> /etc/systemd/system/vault.service

[Unit]
Description="HashiCorp Vault - A tool for managing secrets"
Documentation=https://www.vaultproject.io/docs/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/vault.d/vault.hcl
StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
User=vault
Group=vault
ProtectSystem=full
ProtectHome=read-only
PrivateTmp=yes
PrivateDevices=yes
SecureBits=keep-caps
AmbientCapabilities=CAP_IPC_LOCK
CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK
NoNewPrivileges=yes
ExecStart=/usr/local/bin/vault server -config=/etc/vault.d/
ExecReload=/bin/kill --signal HUP $MAINPID
KillMode=process
KillSignal=SIGINT
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
StartLimitInterval=60
StartLimitBurst=3
LimitNOFILE=65536
LimitMEMLOCK=infinity

[Install]
WantedBy=multi-user.target
EOF


sudo systemctl enable vault.service
sudo systemctl start vault.service

