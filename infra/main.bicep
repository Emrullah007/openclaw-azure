// ============================================================
// OpenClaw on Azure — Main Bicep Template
// Deploys: VNet, NSG, Public IP, NIC, Ubuntu VM
// Budget target: $20–30/month (Standard_B2als_v2)
// ============================================================

targetScope = 'resourceGroup'

@description('Azure region. Defaults to resource group location.')
param location string = resourceGroup().location

@description('Prefix used for all resource names.')
param vmName string = 'openclaw-vm'

@description('Admin username for SSH login.')
param adminUsername string = 'azureuser'

@description('Your SSH public key (contents of ~/.ssh/id_rsa.pub or similar).')
@secure()
param sshPublicKey string

@description('Source IP allowed for SSH. Use your own IP for best security (e.g. "1.2.3.4/32"). Use "*" to allow all (not recommended).')
param allowedSshSourceIp string = '*'

// ── Modules ─────────────────────────────────────────────────

module network 'network.bicep' = {
  name: 'openclaw-network'
  params: {
    location: location
    vmName: vmName
    allowedSshSourceIp: allowedSshSourceIp
  }
}

module vm 'vm.bicep' = {
  name: 'openclaw-vm'
  params: {
    location: location
    vmName: vmName
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    subnetId: network.outputs.subnetId
    nsgId: network.outputs.nsgId
  }
}

// ── Outputs ──────────────────────────────────────────────────

output publicIpAddress string = vm.outputs.publicIpAddress
output sshCommand string = 'ssh ${adminUsername}@${vm.outputs.publicIpAddress}'
output gatewayUrl string = 'http://${vm.outputs.publicIpAddress}:18789'
