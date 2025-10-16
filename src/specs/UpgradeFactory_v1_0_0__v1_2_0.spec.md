# UpgradeFactory_v1_0_0\_\_v1_2_0.sol Specification

## Summary

The UpgradeGaugesFactoryV1_0_0\_\_V1_2_0 contract facilitates the upgrade of a deployed v1.0.0 gauge voting system to v1.2.0. It handles the complex migration from token-based to address-based voting, adds delegation support through IVotes adapter, switches from quadratic to linear curves, and upgrades all core contracts while preserving state and permissions.

1.2.0 avoids adding totalSupply tracking, which adds gas overhead whilst not being possible to accurately add retroactively.

## Mechanism Explanation

The upgrade factory orchestrates a multi-step upgrade process:

### Upgrade Candidates

**Note**: Ideal candidates for this upgrade are DAOs that:

- Do not need on-chain total supply queries for governance

### Major Changes from v1.0.0 to v1.2.0

1. **Voting Model**: TokenGaugeVoter → AddressGaugeVoter (vote by address not NFT)
2. **Curve Implementation**: QuadraticIncreasingCurve → LinearIncreasingCurve without supply tracking
3. **Delegation Support**: Adds EscrowIVotesAdapter for address-based delegation
4. **Lock Start Time**: Locks now start at previous week checkpoint instead of next week
5. **Removed Features**: No more warmup period functionality

### Upgrade Process

1. **State Preservation**: Copies existing deployment and parameters from v1.0.0 factory
2. **Validation**: Uses Foundry's upgrade validation to ensure safe UUPS upgrades
3. **Contract Deployment**: Deploys new IVotes adapter and AddressGaugeVoter implementations
4. **UUPS Upgrades**: Upgrades Clock, Curve, VotingEscrow, and Lock contracts to v1.2.0
5. **Configuration**: Sets the new contracts on VotingEscrow and pauses for safety
6. **Permission Management**: Handles temporary permissions needed for upgrade

## Interface

```solidity
interface IUpgradeGaugesFactoryV1_0_0__V1_2_0 {
  // Structs (Updated versions for v1.2.0)
  struct DeploymentParameters {
    uint16 minApprovals;
    address[] multisigMembers;
    TokenParameters[] tokenParameters;
    uint16 feePercent;
    uint48 warmupPeriod; // Deprecated but kept for compatibility
    uint48 cooldownPeriod;
    uint48 minLockDuration;
    bool votingPaused;
    uint256 minDeposit;
    PluginRepo multisigPluginRepo;
    uint8 multisigPluginRelease;
    uint16 multisigPluginBuild;
    GaugeVoterSetup voterPluginSetup;
    string voterEnsSubdomain;
    address osxDaoFactory;
    PluginSetupProcessor pluginSetupProcessor;
    PluginRepoFactory pluginRepoFactory;
  }

  struct GaugePluginSet {
    AddressGaugeVoter plugin; // Upgraded from TokenGaugeVoter
    LinearIncreasingCurve curve; // Upgraded from QuadraticIncreasingCurve
    ExitQueue exitQueue;
    VotingEscrowV1_2_0 votingEscrow; // Upgraded version
    ClockV1_2_0 clock; // Upgraded version
    LockV1_2_0 nftLock; // Upgraded version
    EscrowIVotesAdapter delegation; // New in v1.2.0
  }

  struct Deployment {
    DAO dao;
    Multisig multisigPlugin;
    GaugePluginSet[] gaugeVoterPluginSets;
    PluginRepo gaugeVoterPluginRepo;
  }

  // Main Functions
  /// @notice Validate that upgrades are safe using Foundry upgrade checker
  function validateUpgrade() external;

  /// @notice Execute the full upgrade from v1.0.0 to v1.2.0
  /// @param validate Whether to run upgrade validation
  /// @param clockUpgrade New Clock implementation
  /// @param curveUpgrade New LinearIncreasingCurve implementation
  /// @param escrowUpgrade New VotingEscrow implementation
  /// @param lockUpgrade New Lock implementation
  /// @param ivotesAdapter IVotes adapter implementation
  /// @param addressGaugeVoter AddressGaugeVoter implementation
  function upgrade(
    bool validate,
    ClockV1_2_0 clockUpgrade,
    LinearIncreasingCurve curveUpgrade,
    VotingEscrowV1_2_0 escrowUpgrade,
    LockV1_2_0 lockUpgrade,
    EscrowIVotesAdapter ivotesAdapter,
    AddressGaugeVoter addressGaugeVoter
  ) external;

  // Permission Management
  /// @notice Get permissions needed for upgrade process
  /// @param _grantOrRevoke Whether to grant or revoke permissions
  /// @param pluginSetIndex Which plugin set to get permissions for
  /// @return Array of multi-target permissions
  function getPermissions(
    PermissionLib.Operation _grantOrRevoke,
    uint pluginSetIndex
  ) external view returns (PermissionLib.MultiTargetPermission[] memory);

  // View Functions
  /// @notice Get the original v1.0.0 deployment
  /// @return Original deployment structure
  function getOldDeployment() external view returns (DeploymentV1_0_0 memory);

  /// @notice Get the upgraded deployment structure
  /// @return Upgraded deployment with v1.2.0 contracts
  function getDeployment() external view returns (Deployment memory);

  // State Variables
  /// @notice Address of the original v1.0.0 factory
  function factory() external view returns (address);

  /// @notice Upgraded deployment structure
  function deployment() external view returns (Deployment memory);

  /// @notice Copied and converted parameters
  function parameters() external view returns (DeploymentParameters memory);
}
```

## Caveats

- **One-way upgrade**: This upgrade cannot be reversed once executed
- **Paused state**: All VotingEscrow contracts are paused after upgrade for safety
- **Manual unpausing**: Admin must unpause contracts after verifying successful upgrade
- **Permission requirements**: Upgrade contract needs temporary admin permissions on all contracts
- **Validation optional**: While validation can be skipped, it's strongly recommended
- **Coefficient validation**: Ensures new contracts use same curve coefficients as original
- **State preservation**: All existing locks, voting power, and NFT ownership is preserved
- **Gas intensive**: The upgrade process requires significant gas for all contract upgrades
