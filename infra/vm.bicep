// ============================================================
// OpenClaw — Virtual Machine
// Size: Standard_B2als_v2 (2 vCPU, 4 GiB RAM, AMD) ~$22-25/month
// OS:   Ubuntu 24.04 LTS
// Auth: SSH key only (no password)
// ============================================================

param location string
param vmName string
param adminUsername string

@secure()
param sshPublicKey string

param subnetId string
param nsgId string

// ── Public IP ────────────────────────────────────────────────

resource publicIp 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: '${vmName}-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: vmName
    }
  }
}

// ── Network Interface ────────────────────────────────────────

resource nic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: '${vmName}-nic'
  location: location
  properties: {
    networkSecurityGroup: {
      id: nsgId
    }
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIp.id
          }
          subnet: {
            id: subnetId
          }
        }
      }
    ]
  }
}

// ── Virtual Machine ──────────────────────────────────────────

resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      // Standard_B2als_v2: 2 vCPU, 4 GiB RAM (AMD) — meets OpenClaw 2GB min
      // To go cheaper: Standard_B1ms (1 vCPU, 2 GiB) ~$15/month but tighter
      vmSize: 'Standard_B2als_v2'
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
        patchSettings: {
          patchMode: 'AutomaticByPlatform'
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
      }
      osDisk: {
        name: '${vmName}-osdisk'
        createOption: 'FromImage'
        managedDisk: {
          // Standard_LRS saves ~$2/month vs Premium. Fine for this workload.
          storageAccountType: 'Standard_LRS'
        }
        diskSizeGB: 32
        deleteOption: 'Delete' // disk deleted when VM is deleted
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
          properties: {
            deleteOption: 'Delete' // NIC deleted when VM is deleted
          }
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true // useful for SSH troubleshooting, no extra cost
      }
    }
  }
}

// ── Outputs ──────────────────────────────────────────────────

output publicIpAddress string = publicIp.properties.ipAddress
output fqdn string = publicIp.properties.dnsSettings.fqdn
output vmId string = vm.id
