# IGaugeManager
[Git Source](https://github.com/aragon/ve-governance/blob/d1db1e959d76056114cf52b0b8a3ff8311778151/src/voting/ISimpleGaugeVoter.sol)

**Inherits:**
[IGaugeManagerEvents](/src/voting/ISimpleGaugeVoter.sol/interface.IGaugeManagerEvents.md), [IGaugeManagerErrors](/src/voting/ISimpleGaugeVoter.sol/interface.IGaugeManagerErrors.md)


## Functions
### isActive


```solidity
function isActive(address gauge) external view returns (bool);
```

### createGauge


```solidity
function createGauge(address _gauge, string calldata _metadata) external returns (address);
```

### deactivateGauge


```solidity
function deactivateGauge(address _gauge) external;
```

### activateGauge


```solidity
function activateGauge(address _gauge) external;
```

### updateGaugeMetadata


```solidity
function updateGaugeMetadata(address _gauge, string calldata _metadata) external;
```

