# Deployment
[Git Source](https://github.com/aragon/ve-governance/blob/d1db1e959d76056114cf52b0b8a3ff8311778151/src/factory/GaugesDaoFactory.sol)

Contains the artifacts that resulted from running a deployment


```solidity
struct Deployment {
    DAO dao;
    Multisig multisigPlugin;
    GaugePluginSet[] gaugeVoterPluginSets;
    PluginRepo gaugeVoterPluginRepo;
}
```

