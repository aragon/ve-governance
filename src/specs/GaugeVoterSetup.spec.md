# GaugeVoterSetup Specification (All Versions)

## Summary

The GaugeVoterSetup contracts are Aragon OSx plugin setup contracts that handle the deployment and configuration of the gauge voting system across different versions. Each version introduces changes while maintaining the core functionality of gauge-based voting with time-locked token positions.

### Aragon OSx Integration

In OSx, setup contracts enable standardized plugin installation on DAOs via the PluginSetupProcessor. By treating the VE system as a "bundle" of plugins (voting plugin + helper contracts), the entire system can be installed atomically through a single governance vote. For new DAOs, the factory contract handles this entire process atomically, ensuring all components are deployed and configured consistently.

## Version Overview

### v1.1.0 - Token-based Voting with Quadratic Curve

- **Voting Plugin**: TokenGaugeVoter_v1_1_0 (NFT token-based voting)
- **Curve**: QuadraticIncreasingCurve (quadratic voting power, no supply tracking)
- **Key Feature**: Allows exits during voting windows
- **Voting Method**: Users vote with specific NFT token IDs

### v1.2.0 - Address-based Voting with Linear Curve

- **Voting Plugin**: AddressGaugeVoter (address-based voting)
- **Curve**: LinearIncreasingCurveNoSupply (linear decay, no supply tracking)
- **Key Features**:
  - Introduced delegation via EscrowIVotesAdapter
  - Removed warmup period
  - Locks start at previous week checkpoint
- **Voting Method**: Users vote from their addresses

### v1.3.0 - Supply Tracking Addition

- **Voting Plugin**: AddressGaugeVoter (same as v1.2.0)
- **Curve**: LinearIncreasingCurve (with global supply tracking)
- **Key Feature**: Added supply checkpointing for on-chain quorum calculations
- **Voting Method**: Same address-based voting as v1.2.0

### v1.4.0 - Dynamic Exit Queue

- **Voting Plugin**: AddressGaugeVoter (same as v1.2.0+)
- **Exit Queue**: DynamicExitQueue (replaces standard ExitQueue)
- **Key Features**:
  - Variable exit fees based on queue state
  - Fee calculations use sqrt and linear curves
  - Emergency exit functionality
- **Voting Method**: Same address-based voting

## Key Interface Functions

```solidity
interface IGaugeVoterSetup {
  // Common Setup Parameters (all versions)
  struct IGaugeVoterSetupParams {
    // Voter configuration
    bool isPaused; // Deploy voter in paused state
    // NFT configuration
    string veTokenName; // Name for voting escrow NFT
    string veTokenSymbol; // Symbol for voting escrow NFT
    // Escrow configuration
    address token; // ERC20 token to lock
    uint256 minDeposit; // Minimum deposit amount
    // Queue configuration
    uint256 feePercent; // Exit fee percentage
    uint48 cooldown; // Exit queue cooldown period
    uint48 minLock; // Minimum lock duration before exit
    // Curve configuration (v1.1.0 only)
    uint48 warmup; // Warmup period for voting power
  }

  // Main Setup Functions

  /// @notice Prepare plugin installation
  /// @param _dao DAO address to install plugin for
  /// @param _data Encoded setup parameters
  /// @return plugin The deployed plugin address
  /// @return preparedSetupData Permissions and helper addresses
  function prepareInstallation(
    address _dao,
    bytes calldata _data
  )
    external
    returns (address plugin, PreparedSetupData memory preparedSetupData);

  /// @notice Prepare plugin uninstallation
  /// @param _dao DAO address
  /// @param _payload Current plugin setup payload
  /// @return permissions Permissions to revoke
  function prepareUninstallation(
    address _dao,
    SetupPayload calldata _payload
  )
    external
    view
    returns (PermissionLib.MultiTargetPermission[] memory permissions);

  // Key Events
  event Deployed(
    address gaugeVoter,
    address votingEscrow,
    address curve,
    address exitQueue,
    address lock,
    address clock
  );

  event DeployedWithAdapter(
    // v1.2.0+ only
    address gaugeVoter,
    address votingEscrow,
    address curve,
    address adapter, // IVotes adapter
    address exitQueue,
    address lock,
    address clock
  );
}
```

## Deployment Differences by Version

### Helper Contract Order

- **v1.1.0**: [curve, queue, escrow, clock, nft]
- **v1.2.0+**: [curve, adapter, queue, escrow, clock, nft]

### Permissions Count

- **v1.1.0**: 10 permissions
- **v1.2.0+**: 11 permissions (adds DELEGATION_ADMIN_ROLE)

### Curve Parameters

- **v1.1.0**: Includes warmup period configuration
- **v1.2.0+**: No warmup period (removed from LinearIncreasingCurve)

## Migration Considerations

### v1.1.0 → v1.2.0

- Requires UpgradeFactory_v1_0_0\_\_v1_3_0 for migration
- Switches from token to address voting
- Adds delegation capability

### v1.2.0 → v1.3.0

- Simple curve swap to enable supply tracking
- No interface changes to main plugin

### v1.3.0 → v1.4.0

- Exit queue upgrade only
- Maintains all other components

## Caveats

- **Helper Array Order**: Must maintain exact order specified per version
- **Implementation Contracts**: All base implementations must be pre-deployed
- **One-time Installation**: Plugins cannot be reinstalled, only uninstalled
- **Version Compatibility**: Each setup version is tied to specific contract versions
- **Delegation Requirement**: v1.2.0+ requires self-delegation for VE voting power
- **Supply Tracking**: Only v1.3.0+ supports on-chain supply queries
- **Dynamic Fees**: Only v1.4.0 supports variable exit fees

