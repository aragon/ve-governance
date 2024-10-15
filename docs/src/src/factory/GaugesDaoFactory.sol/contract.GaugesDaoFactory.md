# GaugesDaoFactory
[Git Source](https://github.com/aragon/ve-governance/blob/d1db1e959d76056114cf52b0b8a3ff8311778151/src/factory/GaugesDaoFactory.sol)

A singleton contract designed to run the deployment once and become a read-only store of the contracts deployed


## State Variables
### parameters

```solidity
DeploymentParameters parameters;
```


### deployment

```solidity
Deployment deployment;
```


## Functions
### constructor

Initializes the factory and performs the full deployment. Values become read-only after that.


```solidity
constructor(DeploymentParameters memory _parameters);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_parameters`|`DeploymentParameters`|The parameters of the one-time deployment.|


### deployOnce

Run the deployment and store the artifacts in a read-only store that can be retrieved via `getDeployment()` and `getDeploymentParameters()`


```solidity
function deployOnce() public;
```

### prepareDao


```solidity
function prepareDao() internal returns (DAO dao);
```

### prepareMultisig


```solidity
function prepareMultisig(DAO dao, PluginRepo.Tag memory repoTag)
    internal
    returns (Multisig, IPluginSetup.PreparedSetupData memory);
```

### prepareSimpleGaugeVoterPluginRepo


```solidity
function prepareSimpleGaugeVoterPluginRepo(DAO dao) internal returns (PluginRepo pluginRepo);
```

### prepareSimpleGaugeVoterPlugin


```solidity
function prepareSimpleGaugeVoterPlugin(
    DAO dao,
    TokenParameters memory tokenParameters,
    PluginRepo pluginRepo,
    PluginRepo.Tag memory repoTag
) internal returns (GaugePluginSet memory, PluginRepo, IPluginSetup.PreparedSetupData memory);
```

### applyPluginInstallation


```solidity
function applyPluginInstallation(
    DAO dao,
    address plugin,
    PluginRepo pluginRepo,
    PluginRepo.Tag memory pluginRepoTag,
    IPluginSetup.PreparedSetupData memory preparedSetupData
) internal;
```

### activateSimpleGaugeVoterInstallation


```solidity
function activateSimpleGaugeVoterInstallation(DAO dao, GaugePluginSet memory pluginSet) internal;
```

### grantApplyInstallationPermissions


```solidity
function grantApplyInstallationPermissions(DAO dao) internal;
```

### revokeApplyInstallationPermissions


```solidity
function revokeApplyInstallationPermissions(DAO dao) internal;
```

### revokeOwnerPermission


```solidity
function revokeOwnerPermission(DAO dao) internal;
```

### getDeploymentParameters


```solidity
function getDeploymentParameters() public view returns (DeploymentParameters memory);
```

### getDeployment


```solidity
function getDeployment() public view returns (Deployment memory);
```

## Errors
### AlreadyDeployed
Thrown when attempting to call deployOnce() when the DAO is already deployed.


```solidity
error AlreadyDeployed();
```

