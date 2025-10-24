# GaugesDaoFactory Specification (All Versions)

## Summary

The GaugesDaoFactory contracts are singleton factories that orchestrate the one-time deployment of complete DAOs with gauge voting capabilities. Each version maintains the same deployment pattern while introducing specific improvements to the gauge voting system components.

## Architecture Overview

All factory versions implement a one-time deployment pattern that creates:

1. **DAO Infrastructure**: New Aragon OSx DAO with UUPS upgradeability
2. **Multisig Plugin**: Administrative control for initial DAO management
3. **Gauge Voting System** (per token):
   - GaugeVoter plugin for gauge weight voting
   - VotingEscrow contract for token locking
   - Curve contract for voting power calculation
   - Exit queue for withdrawal management
   - Clock for time coordination
   - Lock NFT for position representation
   - IVotes adapter for delegation support (v1.2.0+)

## Version Differences

### v1.2.0 - Initial Linear Curve with Delegation

- **Curve**: LinearIncreasingCurveNoSupply (no global supply tracking)
- **Delegation**: Introduces EscrowIVotesAdapter for address-based delegation
- **Exit Queue**: Standard ExitQueue with fixed fees
- **Merge/Split**: introduces escrow merge and split functions

### v1.3.0 - Supply Tracking Addition

- **Curve**: LinearIncreasingCurve with full supply tracking
- **Key Feature**: Enables on-chain supply queries via `supplyAt()` for quorum calculations

### v1.4.0 - Dynamic Exit Fees

- **Exit Queue**: DynamicExitQueue replaces standard ExitQueue
- **Key Feature**: Variable exit fees based on queue state
- **Fee Flexibility**: Supports dynamic, tiered, or fixed fee structures

## Key Interface Functions

```solidity
interface IGaugesDaoFactory {
  // Core Data Structures
  struct DeploymentParameters {
    // Multisig settings
    uint16 minApprovals; // Required approvals for multisig
    address[] multisigMembers; // Initial multisig signers
    bytes multisigMetadata; // Metadata for multisig plugin
    // Gauge Voter parameters
    TokenParameters[] tokenParameters; // Tokens to create gauge systems for
    uint16 feePercent; // Exit fee (fixed or max for dynamic)
    uint48 cooldownPeriod; // Exit queue cooldown in seconds
    uint48 minLockDuration; // Minimum lock time before exit
    bool votingPaused; // Start with voting paused
    uint256 minDeposit; // Minimum deposit amount
    // Plugin setup and ENS
    PluginRepo multisigPluginRepo; // Multisig plugin repository
    uint8 multisigPluginRelease; // Multisig release version
    uint16 multisigPluginBuild; // Multisig build number
    GaugeVoterSetup voterPluginSetup; // Version-specific setup contract
    string voterEnsSubdomain; // ENS subdomain for plugin repo
    // OSx infrastructure
    address osxDaoFactory; // OSx DAO factory
    PluginSetupProcessor pluginSetupProcessor;
    PluginRepoFactory pluginRepoFactory;
  }

  struct TokenParameters {
    address token; // ERC20 token to lock
    string veTokenName; // Voting escrow NFT name
    string veTokenSymbol; // Voting escrow NFT symbol
  }

  struct Deployment {
    DAO dao; // Deployed DAO instance
    Multisig multisigPlugin; // Administrative multisig
    GaugePluginSet[] gaugeVoterPluginSets; // Gauge systems per token
    PluginRepo gaugeVoterPluginRepo; // Plugin repository
  }

  // Main Function
  /// @notice Deploy the entire DAO system (one-time only)
  function deployOnce() external;

  /// @notice Get the factory version
  function version() external pure returns (string memory);

  /// @notice Get deployment parameters
  function parameters() external view returns (DeploymentParameters memory);

  /// @notice Get deployment result
  function deployment() external view returns (Deployment memory);

  // Key Error
  error AlreadyDeployed();
}
```

## Deployment Flow

1. **Pre-deployment Setup**:

   - Deploy version-specific GaugeVoterSetup contract
   - Configure all deployment parameters in factory constructor

2. **Atomic Deployment**:

   - Create new DAO with temporary DEPLOYER permissions
   - Install multisig plugin for governance
   - For each token:
     - Deploy gauge voting plugin via setup contract
     - Configure all helper contracts
     - Set up proper permissions
   - Create plugin repository for future upgrades
   - Clean up temporary permissions

3. **Post-deployment State**:
   - Factory marked as deployed (prevents redeployment)
   - All contracts properly initialized and connected
   - DAO ready for use with multisig governance

## Multi-token Support

Factories support deploying multiple gauge voting systems in a single transaction:

- Each token gets its own complete gauge voting infrastructure
- All systems share the same DAO and multisig governance
- Useful in systems that want dual governance without having to account for different tokens having different values

## Caveats

- **One-time Use**: Each factory can only deploy once due to singleton pattern
- **Setup Contract Dependency**: Must deploy correct version of GaugeVoterSetup first
- **Version Matching**: Factory version must match setup contract version
- **Gas Costs**: Multi-token deployments can be gas intensive
- **Permission Management**: Temporary DEPLOYER permissions cleaned up after deployment
- **ENS Requirement**: Requires valid ENS subdomain for plugin repository
- **Immutable Parameters**: Cannot change deployment parameters after factory creation
- **No Partial Deployment**: Either all components deploy successfully or transaction reverts

