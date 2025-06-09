#!/usr/bin/env node

const fs = require('fs')
const path = require('path')

/**
 * Script to read latest contract addresses from Foundry broadcast folder
 * Usage: node scripts/readDeploymentAddresses.js [chainId]
 */

const BROADCAST_DIR = './broadcast'

// Common chain IDs
const CHAIN_NAMES = {
  1: 'Ethereum Mainnet',
  11155111: 'Sepolia Testnet',
  421614: 'Arbitrum Sepolia',
  43113: 'Avalanche Fuji',
  11155420: 'Optimism Sepolia',
  137: 'Polygon Mainnet',
  42161: 'Arbitrum One',
  10: 'Optimism Mainnet',
  43114: 'Avalanche Mainnet',
}

function getLatestRunFile(scriptPath, chainId) {
  const chainPath = path.join(scriptPath, chainId)

  if (!fs.existsSync(chainPath)) {
    return null
  }

  const files = fs
    .readdirSync(chainPath)
    .filter((file) => file.startsWith('run-') && file.endsWith('.json'))
    .filter((file) => file !== 'run-latest.json') // Exclude symlink

  if (files.length === 0) {
    return null
  }

  // Sort by timestamp (newest first)
  files.sort((a, b) => {
    const timestampA = parseInt(a.replace('run-', '').replace('.json', ''))
    const timestampB = parseInt(b.replace('run-', '').replace('.json', ''))
    return timestampB - timestampA
  })

  return path.join(chainPath, files[0])
}

function extractContractsFromRun(runFilePath) {
  try {
    const data = JSON.parse(fs.readFileSync(runFilePath, 'utf8'))
    const contracts = {}

    if (data.transactions && Array.isArray(data.transactions)) {
      data.transactions.forEach((tx) => {
        if (
          tx.contractName &&
          tx.contractAddress &&
          tx.transactionType === 'CREATE'
        ) {
          contracts[tx.contractName] = tx.contractAddress
        }
      })
    }

    // Get timestamp from filename or data
    const filename = path.basename(runFilePath)
    const timestamp = filename.match(/run-(\d+)\.json/)?.[1]
    const deploymentTime = timestamp
      ? new Date(parseInt(timestamp) * 1000)
      : null

    return {
      contracts,
      timestamp: deploymentTime,
      file: runFilePath,
    }
  } catch (error) {
    console.error(`Error reading ${runFilePath}:`, error.message)
    return null
  }
}

function getAvailableChains() {
  const chains = new Set()

  if (!fs.existsSync(BROADCAST_DIR)) {
    return []
  }

  const scriptDirs = fs
    .readdirSync(BROADCAST_DIR)
    .filter((item) => fs.statSync(path.join(BROADCAST_DIR, item)).isDirectory())

  scriptDirs.forEach((scriptDir) => {
    const scriptPath = path.join(BROADCAST_DIR, scriptDir)
    const chainDirs = fs
      .readdirSync(scriptPath)
      .filter((item) => fs.statSync(path.join(scriptPath, item)).isDirectory())
      .filter((item) => /^\d+$/.test(item)) // Only numeric chain IDs

    chainDirs.forEach((chainId) => chains.add(chainId))
  })

  return Array.from(chains).sort()
}

function readAllDeployments(targetChainId = null) {
  if (!fs.existsSync(BROADCAST_DIR)) {
    console.log('❌ Broadcast directory not found:', BROADCAST_DIR)
    return
  }

  const scriptDirs = fs
    .readdirSync(BROADCAST_DIR)
    .filter((item) => fs.statSync(path.join(BROADCAST_DIR, item)).isDirectory())

  if (scriptDirs.length === 0) {
    console.log('❌ No deployment scripts found in broadcast directory')
    return
  }

  const availableChains = getAvailableChains()

  if (targetChainId && !availableChains.includes(targetChainId)) {
    console.log(
      `❌ Chain ID ${targetChainId} not found. Available chains:`,
      availableChains.join(', '),
    )
    return
  }

  const chainsToProcess = targetChainId ? [targetChainId] : availableChains

  chainsToProcess.forEach((chainId) => {
    const chainName = CHAIN_NAMES[chainId] || `Chain ${chainId}`

    console.log(`\n🔗 ${chainName} (Chain ID: ${chainId})`)
    console.log('='.repeat(60))

    let hasDeployments = false

    scriptDirs.forEach((scriptDir) => {
      const scriptPath = path.join(BROADCAST_DIR, scriptDir)
      const latestRun = getLatestRunFile(scriptPath, chainId)

      if (!latestRun) {
        return // Skip if no deployments for this chain
      }

      const deployment = extractContractsFromRun(latestRun)
      if (!deployment || Object.keys(deployment.contracts).length === 0) {
        return // Skip if no contracts found
      }

      hasDeployments = true

      console.log(`\n📜 ${scriptDir.replace('.s.sol', '')}`)
      console.log(
        `   Deployed: ${
          deployment.timestamp
            ? deployment.timestamp.toLocaleString()
            : 'Unknown'
        }`,
      )
      console.log(`   File: ${deployment.file}`)

      Object.entries(deployment.contracts).forEach(([name, address]) => {
        console.log(`   📍 ${name}: ${address}`)
      })
    })

    if (!hasDeployments) {
      console.log('   No deployments found for this chain')
    }
  })
}

function generateEnvFile(chainId) {
  if (!chainId) {
    console.log('❌ Chain ID required for .env generation')
    return
  }

  const scriptDirs = fs
    .readdirSync(BROADCAST_DIR)
    .filter((item) => fs.statSync(path.join(BROADCAST_DIR, item)).isDirectory())

  let envContent = `# Contract addresses for Chain ID: ${chainId}\n`
  envContent += `# Generated on: ${new Date().toISOString()}\n\n`

  let foundContracts = false

  scriptDirs.forEach((scriptDir) => {
    const scriptPath = path.join(BROADCAST_DIR, scriptDir)
    const latestRun = getLatestRunFile(scriptPath, chainId)

    if (!latestRun) return

    const deployment = extractContractsFromRun(latestRun)
    if (!deployment || Object.keys(deployment.contracts).length === 0) return

    foundContracts = true
    envContent += `# ${scriptDir.replace('.s.sol', '')} contracts\n`

    Object.entries(deployment.contracts).forEach(([name, address]) => {
      const envVarName = name
        .toUpperCase()
        .replace(/([A-Z])/g, '_$1')
        .replace(/^_/, '')
      envContent += `${envVarName}_ADDRESS=${address}\n`
    })

    envContent += '\n'
  })

  if (!foundContracts) {
    console.log(`❌ No contracts found for chain ID ${chainId}`)
    return
  }

  const envFileName = `.env.${chainId}`
  fs.writeFileSync(envFileName, envContent)
  console.log(`✅ Environment file generated: ${envFileName}`)
}

function generateAddressesJson() {
  const addressesFile = 'addresses.json'

  if (!fs.existsSync(BROADCAST_DIR)) {
    console.log('❌ Broadcast directory not found:', BROADCAST_DIR)
    return
  }

  const scriptDirs = fs
    .readdirSync(BROADCAST_DIR)
    .filter((item) => fs.statSync(path.join(BROADCAST_DIR, item)).isDirectory())

  if (scriptDirs.length === 0) {
    console.log('❌ No deployment scripts found in broadcast directory')
    return
  }

  const addressesData = {
    metadata: {
      lastUpdated: new Date().toISOString(),
      generatedBy: 'readDeploymentAddresses.js',
      version: '1.0.0',
    },
    networks: {},
  }

  const availableChains = getAvailableChains()

  availableChains.forEach((chainId) => {
    const chainName = CHAIN_NAMES[chainId] || `Chain ${chainId}`

    addressesData.networks[chainId] = {
      name: chainName,
      chainId: parseInt(chainId),
      deployments: {},
    }

    let hasDeployments = false

    scriptDirs.forEach((scriptDir) => {
      const scriptPath = path.join(BROADCAST_DIR, scriptDir)
      const latestRun = getLatestRunFile(scriptPath, chainId)

      if (!latestRun) return

      const deployment = extractContractsFromRun(latestRun)
      if (!deployment || Object.keys(deployment.contracts).length === 0) return

      hasDeployments = true
      const scriptName = scriptDir.replace('.s.sol', '')

      addressesData.networks[chainId].deployments[scriptName] = {
        timestamp: deployment.timestamp
          ? deployment.timestamp.toISOString()
          : null,
        file: deployment.file,
        contracts: deployment.contracts,
      }
    })

    // Remove networks with no deployments
    if (!hasDeployments) {
      delete addressesData.networks[chainId]
    }
  })

  // Write the JSON file
  fs.writeFileSync(addressesFile, JSON.stringify(addressesData, null, 2))
  console.log(`✅ Addresses file generated: ${addressesFile}`)

  // Show summary
  const networkCount = Object.keys(addressesData.networks).length
  let totalContracts = 0

  Object.values(addressesData.networks).forEach((network) => {
    Object.values(network.deployments).forEach((deployment) => {
      totalContracts += Object.keys(deployment.contracts).length
    })
  })

  console.log(
    `📊 Summary: ${networkCount} networks, ${totalContracts} contracts total`,
  )

  return addressesData
}

function updateAddressesFile() {
  console.log('🔄 Updating addresses.json...')
  return generateAddressesJson()
}

function main() {
  const args = process.argv.slice(2)
  const command = args[0]
  const chainId = args[1]

  console.log('🚀 Alioth Contract Address Reader')
  console.log('='.repeat(40))

  if (command === '--env' || command === '-e') {
    generateEnvFile(chainId)
    return
  }

  if (command === '--json' || command === '-j') {
    generateAddressesJson()
    return
  }

  if (command === '--chains' || command === '-c') {
    const chains = getAvailableChains()
    console.log('\n📋 Available Chain IDs:')
    chains.forEach((id) => {
      const name = CHAIN_NAMES[id] || 'Unknown'
      console.log(`   ${id}: ${name}`)
    })
    return
  }

  if (command === '--help' || command === '-h') {
    console.log(`
Usage:
  node scripts/readDeploymentAddresses.js [chainId]
  
Options:
  [chainId]                Show deployments for specific chain ID
  --chains, -c            List available chain IDs
  --env [chainId], -e     Generate .env file for chain ID
  --json, -j              Generate addresses.json file
  --help, -h              Show this help message

Examples:
  node scripts/readDeploymentAddresses.js                # Show all deployments + update addresses.json
  node scripts/readDeploymentAddresses.js 11155111       # Show Sepolia deployments + update addresses.json
  node scripts/readDeploymentAddresses.js --chains       # List available chains
  node scripts/readDeploymentAddresses.js --env 11155111 # Generate .env.11155111
  node scripts/readDeploymentAddresses.js --json         # Generate addresses.json only
`)
    return
  }

  // Always update addresses.json when showing deployments
  readAllDeployments(command) // First arg is chainId if provided

  // Auto-generate addresses.json after reading deployments
  console.log('\n🔄 Auto-updating addresses.json...')
  generateAddressesJson()
}

if (require.main === module) {
  main()
}

module.exports = {
  readAllDeployments,
  getAvailableChains,
  extractContractsFromRun,
  generateEnvFile,
  generateAddressesJson,
  updateAddressesFile,
}
