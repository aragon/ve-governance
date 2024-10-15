# GaugePluginSet
[Git Source](https://github.com/aragon/ve-governance/blob/d1db1e959d76056114cf52b0b8a3ff8311778151/src/factory/GaugesDaoFactory.sol)

Struct containing the plugin and all of its helpers


```solidity
struct GaugePluginSet {
    SimpleGaugeVoter plugin;
    QuadraticIncreasingEscrow curve;
    ExitQueue exitQueue;
    VotingEscrow votingEscrow;
    Clock clock;
    Lock nftLock;
}
```

