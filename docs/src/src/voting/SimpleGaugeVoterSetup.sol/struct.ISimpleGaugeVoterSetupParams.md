# ISimpleGaugeVoterSetupParams
[Git Source](https://github.com/aragon/ve-governance/blob/d1db1e959d76056114cf52b0b8a3ff8311778151/src/voting/SimpleGaugeVoterSetup.sol)

SPDX-License-Identifier: MIT


```solidity
struct ISimpleGaugeVoterSetupParams {
    bool isPaused;
    string veTokenName;
    string veTokenSymbol;
    address token;
    uint256 minDeposit;
    uint256 feePercent;
    uint48 cooldown;
    uint48 minLock;
    uint48 warmup;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`isPaused`|`bool`|Whether the voter contract is deployed in a paused state|
|`veTokenName`|`string`|The name of the voting escrow token|
|`veTokenSymbol`|`string`|The symbol of the voting escrow token|
|`token`|`address`|The underlying token for the escrow|
|`minDeposit`|`uint256`||
|`feePercent`|`uint256`||
|`cooldown`|`uint48`|The cooldown period for the exit queue|
|`minLock`|`uint48`||
|`warmup`|`uint48`|The warmup period for the escrow curve|

