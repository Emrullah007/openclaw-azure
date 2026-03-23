// ============================================================
// OpenClaw — Networking (VNet, Subnet, NSG, Public IP)
// ============================================================

param location string
param vmName string

@description('Source IP for SSH. Restrict to your own IP for security.')
param allowedSshSourceIp string

// ── Network Security Group ───────────────────────────────────

resource nsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: '${vmName}-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-SSH'
        properties: {
          priority: 1000
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: allowedSshSourceIp
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
          description: 'SSH access — restrict to your IP in parameters.json'
        }
      }
      // OpenClaw gateway (18789) is NOT exposed publicly.
      // Access via SSH tunnel: ssh -L 18789:localhost:18789 <admin-username>@<vm-ip>
      // To open publicly later, add a rule here and update the VM NSG.
      {
        name: 'Deny-All-Inbound'
        properties: {
          priority: 4096
          protocol: '*'
          access: 'Deny'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
          description: 'Deny everything else inbound'
        }
      }
    ]
  }
}

// ── Virtual Network ──────────────────────────────────────────

resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: '${vmName}-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: ['10.0.0.0/16']
    }
    subnets: [
      {
        name: 'default'
        properties: {
          addressPrefix: '10.0.1.0/24'
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

// ── Outputs ──────────────────────────────────────────────────

output subnetId string = vnet.properties.subnets[0].id
