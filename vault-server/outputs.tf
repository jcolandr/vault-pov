
output "endpoints" {
  value = <<EOF

Vault Server IP (public):  ${join(", ", azurerm_linux_virtual_machine.myvaultvm.*.public_ip_address)}
Vault Server IP (private): ${join(", ", azurerm_linux_virtual_machine.myvaultvm.*.private_ip_address)}

chmod 600 key.pem
ssh -i key.pem azureuser@${azurerm_linux_virtual_machine.myvaultvm.public_ip_address}
export VAULT_ADDR=http://${azurerm_linux_virtual_machine.myvaultvm.public_ip_address}:8200
open $VAULT_ADDR/ui

EOF

}


