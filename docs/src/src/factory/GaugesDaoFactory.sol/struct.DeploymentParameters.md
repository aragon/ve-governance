# DeploymentParameters
[Git Source](https://github.com/aragon/ve-governance/blob/d1db1e959d76056114cf52b0b8a3ff8311778151/src/factory/GaugesDaoFactory.sol)

The struct containing all the parameters to deploy the DAO


```solidity
struct DeploymentParameters {
    uint16 minApprovals;
    address[] multisigMembers;
    TokenParameters[] tokenParameters;
    uint16 feePercent;
    uint48 warmupPeriod;
    uint48 cooldownPeriod;
    uint48 minLockDuration;
    bool votingPaused;
    uint256 minDeposit;
    PluginRepo multisigPluginRepo;
    uint8 multisigPluginRelease;
    uint16 multisigPluginBuild;
    SimpleGaugeVoterSetup voterPluginSetup;
    string voterEnsSubdomain;
    address osxDaoFactory;
    PluginSetupProcessor pluginSetupProcessor;
    PluginRepoFactory pluginRepoFactory;
}
```

**Properties**

|Name|Type|Description|
|----|----|-----------|
|`minApprovals`|`uint16`|The amount of approvals required for the multisig to be able to execute a proposal on the DAO|
|`multisigMembers`|`address[]`|The list of addresses to be defined as the initial multisig signers|
|`tokenParameters`|`TokenParameters[]`|A list with the tokens and metadata for which a plugin and a VE should be deployed|
|`feePercent`|`uint16`|The fee taken on withdrawals (1 ether = 100%)|
|`warmupPeriod`|`uint48`|Delay in seconds after depositing before voting becomes possible|
|`cooldownPeriod`|`uint48`|Delay seconds after queuing an exit before withdrawing becomes possible|
|`minLockDuration`|`uint48`|Min seconds a user must have locked in escrow before they can queue an exit|
|`votingPaused`|`bool`|Prevent voting until manually activated by the multisig|
|`minDeposit`|`uint256`||
|`multisigPluginRepo`|`PluginRepo`|Address of Aragon's multisig plugin repository on the given network|
|`multisigPluginRelease`|`uint8`|The release of the multisig plugin to target|
|`multisigPluginBuild`|`uint16`|The build of the multisig plugin to target|
|`voterPluginSetup`|`SimpleGaugeVoterSetup`|The address of the Gauges Voter plugin setup contract to create a repository with|
|`voterEnsSubdomain`|`string`|The ENS subdomain under which the plugin reposiroty will be created|
|`osxDaoFactory`|`address`|The address of the OSx DAO factory contract, used to retrieve the DAO implementation address|
|`pluginSetupProcessor`|`PluginSetupProcessor`|The address of the OSx PluginSetupProcessor contract on the target chain|
|`pluginRepoFactory`|`PluginRepoFactory`|The address of the OSx PluginRepoFactory contract on the target chain|

