// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "@test/constants.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginRepoRegistry} from "@aragon/osx/framework/plugin/repo/PluginRepoRegistry.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import {
    Multisig,
    MultisigSetup as MultisigPluginSetup
} from "@aragon/multisig/src/MultisigSetup.sol";
import {
    hashHelpers,
    PluginSetupRef
} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";

import {
    GaugeVoterSetup,
    VotingEscrow,
    Clock,
    Lock,
    Curve,
    ExitQueue,
    GaugeVoter as TokenGaugeVoter,
    IGaugeVoterSetupParams
} from "@setup/GaugeVoterSetup.sol";
import {
    GaugesDaoFactory,
    Deployment as DeploymentV1_0_0,
    DeploymentParameters as DeploymentParametersV1_0_0,
    GaugePluginSet as GaugePluginSetV1_0_0
} from "../GaugesDaoFactory.sol";

import {
    Clock as ClockV1_2_0,
    Curve as LinearIncreasingCurve,
    GaugeVoter as AddressGaugeVoter,
    VotingEscrow as VotingEscrowV1_2_0,
    GaugeVoterSetupV1_3_0,
    IGaugeVoterSetupParams as IGaugeVoterSetupParamsV1_3_0,
    EscrowIVotesAdapter,
    Lock as LockV1_2_0
} from "@setup/GaugeVoterSetup_v1_3_0.sol";

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {ProxyLib} from "@libs/ProxyLib.sol";

import {Upgrades} from "@foundry-upgrades/src/LegacyUpgrades.sol";
import {Options} from "@foundry-upgrades/src/Options.sol";

import {CurveConstantLib} from "@libs/CurveConstantLib.sol";

interface IFactory {
    function getDeployment() external view returns (DeploymentV1_0_0 memory);
    function getDeploymentParameters() external view returns (DeploymentParametersV1_0_0 memory);
}

/// @notice The struct containing all the parameters to deploy the DAO
/// @param minApprovals The amount of approvals required for the multisig to be able to execute a proposal on the DAO
/// @param multisigMembers The list of addresses to be defined as the initial multisig signers
/// @param tokenParameters A list with the tokens and metadata for which a plugin and a VE should be deployed
/// @param feePercent The fee taken on withdrawals (1 ether = 100%)
/// @param warmupPeriod Delay in seconds after depositing before voting becomes possible
/// @param cooldownPeriod Delay seconds after queuing an exit before withdrawing becomes possible
/// @param minLockDuration Min seconds a user must have locked in escrow before they can queue an exit
/// @param votingPaused Prevent voting until manually activated by the multisig
/// @param multisigPluginRepo Address of Aragon's multisig plugin repository on the given network
/// @param multisigPluginRelease The release of the multisig plugin to target
/// @param multisigPluginBuild The build of the multisig plugin to target
/// @param voterPluginSetup The address of the Gauges Voter plugin setup contract to create a repository with
/// @param voterEnsSubdomain The ENS subdomain under which the plugin reposiroty will be created
/// @param osxDaoFactory The address of the OSx DAO factory contract, used to retrieve the DAO implementation address
/// @param pluginSetupProcessor The address of the OSx PluginSetupProcessor contract on the target chain
/// @param pluginRepoFactory The address of the OSx PluginRepoFactory contract on the target chain
struct DeploymentParameters {
    // Multisig settings
    uint16 minApprovals;
    address[] multisigMembers;
    // Gauge Voter
    TokenParameters[] tokenParameters;
    uint16 feePercent;
    uint48 warmupPeriod;
    uint48 cooldownPeriod;
    uint48 minLockDuration;
    bool votingPaused;
    uint256 minDeposit;
    // Voter plugin setup and ENS
    PluginRepo multisigPluginRepo;
    uint8 multisigPluginRelease;
    uint16 multisigPluginBuild;
    GaugeVoterSetup voterPluginSetup;
    string voterEnsSubdomain;
    // OSx addresses
    address osxDaoFactory;
    PluginSetupProcessor pluginSetupProcessor;
    PluginRepoFactory pluginRepoFactory;
}

struct TokenParameters {
    address token;
    string veTokenName;
    string veTokenSymbol;
}

/// @notice Struct containing the plugin and all of its helpers
struct GaugePluginSet {
    AddressGaugeVoter plugin;
    LinearIncreasingCurve curve;
    ExitQueue exitQueue;
    VotingEscrowV1_2_0 votingEscrow;
    ClockV1_2_0 clock;
    LockV1_2_0 nftLock;
    EscrowIVotesAdapter delegation;
}

/// @notice Contains the artifacts that resulted from running a deployment
struct Deployment {
    DAO dao;
    // Plugins
    Multisig multisigPlugin;
    GaugePluginSet[] gaugeVoterPluginSets;
    // Plugin repo's
    PluginRepo gaugeVoterPluginRepo;
}

contract UpgradeGaugesFactoryV1_0_0__V1_3_0 {
    using Address for address;
    using Clones for address;
    using ERC165Checker for address;
    using ProxyLib for address;

    address factory;

    Deployment deployment;
    DeploymentParameters parameters;

    constructor(address _factory) {
        factory = _factory;

        DeploymentV1_0_0 memory oldDeployment = IFactory(factory).getDeployment();

        // init with the old contracts, as needed we will overwrite
        for (uint i = 0; i < oldDeployment.gaugeVoterPluginSets.length; i++) {
            GaugePluginSetV1_0_0 memory oldPluginSet = oldDeployment.gaugeVoterPluginSets[i];

            GaugePluginSet memory newPluginSet;

            // copy the contracts over - for now casting them
            // todo good idea?
            newPluginSet.plugin = AddressGaugeVoter(address(oldPluginSet.plugin));
            newPluginSet.curve = LinearIncreasingCurve(address(oldPluginSet.curve));
            newPluginSet.votingEscrow = VotingEscrowV1_2_0(address(oldPluginSet.votingEscrow));
            newPluginSet.clock = ClockV1_2_0(address(oldPluginSet.clock));
            newPluginSet.nftLock = LockV1_2_0(address(oldPluginSet.nftLock));
            newPluginSet.exitQueue = oldPluginSet.exitQueue;

            deployment.gaugeVoterPluginSets.push(newPluginSet);
        }

        deployment.dao = oldDeployment.dao;
        deployment.multisigPlugin = oldDeployment.multisigPlugin;
        deployment.gaugeVoterPluginRepo = oldDeployment.gaugeVoterPluginRepo;

        // copy the parameters over
        DeploymentParametersV1_0_0 memory oldParameters = IFactory(factory)
            .getDeploymentParameters();
        parameters.minApprovals = oldParameters.minApprovals;

        for (uint i = 0; i < oldParameters.multisigMembers.length; i++) {
            parameters.multisigMembers.push(oldParameters.multisigMembers[i]);
        }

        for (uint i = 0; i < oldParameters.tokenParameters.length; i++) {
            // typecast the old token parameters to the new struct
            TokenParameters memory castedOldParameters = abi.decode(
                abi.encode(oldParameters.tokenParameters[i]),
                (TokenParameters)
            );
            parameters.tokenParameters.push(castedOldParameters);
        }

        parameters.feePercent = oldParameters.feePercent;
        parameters.warmupPeriod = oldParameters.warmupPeriod;
        parameters.cooldownPeriod = oldParameters.cooldownPeriod;
        parameters.minLockDuration = oldParameters.minLockDuration;
        parameters.votingPaused = oldParameters.votingPaused;
        parameters.minDeposit = oldParameters.minDeposit;
        parameters.multisigPluginRepo = oldParameters.multisigPluginRepo;
        parameters.multisigPluginRelease = oldParameters.multisigPluginRelease;
        parameters.multisigPluginBuild = oldParameters.multisigPluginBuild;
        parameters.osxDaoFactory = oldParameters.osxDaoFactory;
        parameters.pluginSetupProcessor = oldParameters.pluginSetupProcessor;
        parameters.pluginRepoFactory = oldParameters.pluginRepoFactory;
        parameters.voterPluginSetup = oldParameters.voterPluginSetup;
        parameters.voterEnsSubdomain = oldParameters.voterEnsSubdomain;
    }

    function validateUpgrade() public {
        Options memory options;

        string[] memory exclude = new string[](1);
        // disable initializers is invoked but the custom unsafe allow option is not set in the natspec
        exclude[0] = "lib/osx/packages/contracts/src/core/plugin/PluginUUPSUpgradeable.sol";
        options.exclude = exclude;

        options.referenceContract = "Clock.sol";
        Upgrades.validateUpgrade("Clock_v1_2_0.sol:ClockV1_2_0", options);

        options.referenceContract = "VotingEscrowIncreasing.sol:VotingEscrow";
        Upgrades.validateUpgrade("VotingEscrowIncreasing_v1_2_0.sol:VotingEscrowV1_2_0", options);

        options.referenceContract = "Lock.sol";
        Upgrades.validateUpgrade("Lock_v1_2_0.sol:LockV1_2_0", options);

        options.referenceContract = "QuadraticIncreasingCurve.sol:QuadraticIncreasingEscrow";
        Upgrades.validateUpgrade("LinearIncreasingCurve.sol:LinearIncreasingCurve", options);
    }

    function upgrade(
        bool validate,
        ClockV1_2_0 clockUpgrade,
        LinearIncreasingCurve curveUpgrade,
        VotingEscrowV1_2_0 escrowUpgrade,
        LockV1_2_0 lockUpgrade,
        EscrowIVotesAdapter ivotesAdapter,
        AddressGaugeVoter addressGaugeVoter
    ) public {
        if (validate) {
            validateUpgrade();

            for (uint i = 0; i < parameters.tokenParameters.length; i++) {
                GaugePluginSet memory pluginSet = deployment.gaugeVoterPluginSets[i];
                // make sure that ivotesAdapter is using the same constants
                // as the curve that was already deployed prior.
                int256[3] memory coefficients = pluginSet.curve.getCoefficients(1);
                require(
                    CurveConstantLib.SHARED_CONSTANT_COEFFICIENT == coefficients[0],
                    "invalid constant coefficient"
                );
                require(
                    CurveConstantLib.SHARED_LINEAR_COEFFICIENT == coefficients[1],
                    "invalid linear coefficient"
                );
            }
        }

        _deployEscrowIVotesAdapter(address(ivotesAdapter));
        _deployAddressGaugeVoter(address(addressGaugeVoter));

        _upgradeContracts(clockUpgrade, curveUpgrade, escrowUpgrade, lockUpgrade);
        
        // deploy an address gauge voter that must be used on the upgraded escrow contract.

        // set the ivotes adapter on the escrow
        _setEscrowIVotesAdapter();
        
        // set the address gauge voter on the escrow(before upgrade, it was token gauge voter)
        _setAddressGaugeVoter();
    }

    ////////////////////////////////////////////////
    ///-------------- Internal ------------------///
    ////////////////////////////////////////////////

    function _upgradeContracts(
        ClockV1_2_0 clockUpgrade,
        LinearIncreasingCurve curveUpgrade,
        VotingEscrowV1_2_0 escrowUpgrade,
        LockV1_2_0 lockUpgrade
    ) internal {
        for (uint i = 0; i < parameters.tokenParameters.length; i++) {
            GaugePluginSet memory pluginSet = deployment.gaugeVoterPluginSets[i];

            pluginSet.clock.upgradeTo(address(clockUpgrade));
            pluginSet.curve.upgradeTo(address(curveUpgrade));
            pluginSet.votingEscrow.upgradeTo(address(escrowUpgrade));
            pluginSet.nftLock.upgradeTo(address(lockUpgrade));

            // We only need to pause escrow as other contracts' state changing 
            // functions can only be called by escrow and ivotesAdapter. 
            // Note that `AddressGaugeVoter` and `iVotesAdapter` are by default paused 
            // at the time of deployment.
            pluginSet.votingEscrow.pause();
        }
    }

    function _deployEscrowIVotesAdapter(address base) internal {
        bool startPaused = true;

        // set the delegation mapper in the plugin set
        for (uint i = 0; i < deployment.gaugeVoterPluginSets.length; i++) {
            address delegation = base.deployUUPSProxy(
                abi.encodeCall(
                    EscrowIVotesAdapter.initialize,
                    (
                        address(deployment.dao),
                        address(deployment.gaugeVoterPluginSets[i].votingEscrow),
                        address(deployment.gaugeVoterPluginSets[i].clock),
                        startPaused
                    )
                )
            );
            deployment.gaugeVoterPluginSets[i].delegation = EscrowIVotesAdapter(delegation);
        }
    }

    function _deployAddressGaugeVoter(address _base) internal {
        bool startPaused = true;
        bool enableUpdateVotingPowerHook = true;

        for (uint i = 0; i < deployment.gaugeVoterPluginSets.length; i++) {
            address plugin = _base.deployUUPSProxy(
                abi.encodeCall(
                    AddressGaugeVoter.initialize,
                    (
                        address(deployment.dao),
                        address(deployment.gaugeVoterPluginSets[i].votingEscrow),
                        startPaused,
                        address(deployment.gaugeVoterPluginSets[i].clock),
                        address(deployment.gaugeVoterPluginSets[i].delegation),
                        enableUpdateVotingPowerHook
                    )
                )
            );
            deployment.gaugeVoterPluginSets[i].plugin = AddressGaugeVoter(plugin);
        }
    }

    function _setEscrowIVotesAdapter() internal {
        // set the delegation mapper in the plugin set
        for (uint i = 0; i < deployment.gaugeVoterPluginSets.length; i++) {
            EscrowIVotesAdapter ivotesAdapter = deployment.gaugeVoterPluginSets[i].delegation;
            VotingEscrowV1_2_0 votingEscrow = deployment.gaugeVoterPluginSets[i].votingEscrow;

            votingEscrow.setIVotesAdapter(address(ivotesAdapter));
        }
    }

    function _setAddressGaugeVoter() internal {
        // set the address gauge voter on the escrow
        for (uint i = 0; i < deployment.gaugeVoterPluginSets.length; i++) {
            AddressGaugeVoter addrGaugeVoter = deployment.gaugeVoterPluginSets[i].plugin;
            VotingEscrowV1_2_0 votingEscrow = deployment.gaugeVoterPluginSets[i].votingEscrow;

            votingEscrow.setVoter(address(addrGaugeVoter));
        }
    }

    ////////////////////////////////////////////////
    ///---------------- View -------------------///
    ///////////////////////////////////////////////

    /// @notice Returns the permissions required for the upgrade install and uninstall.
    /// @param _grantOrRevoke The operation to perform
    function getPermissions(
        PermissionLib.Operation _grantOrRevoke,
        uint pluginSetIndex
    ) public view returns (PermissionLib.MultiTargetPermission[] memory) {
        PermissionLib.MultiTargetPermission[]
            memory permissions = new PermissionLib.MultiTargetPermission[](6);

        address here = address(this);
        GaugePluginSet memory p = deployment.gaugeVoterPluginSets[pluginSetIndex];

        permissions[0] = PermissionLib.MultiTargetPermission({
            permissionId: p.votingEscrow.ESCROW_ADMIN_ROLE(),
            where: address(p.votingEscrow),
            who: here,
            operation: _grantOrRevoke,
            condition: PermissionLib.NO_CONDITION
        });

        permissions[1] = PermissionLib.MultiTargetPermission({
            permissionId: p.curve.CURVE_ADMIN_ROLE(),
            where: address(p.curve),
            who: here,
            operation: _grantOrRevoke,
            condition: PermissionLib.NO_CONDITION
        });

        permissions[2] = PermissionLib.MultiTargetPermission({
            permissionId: p.plugin.UPGRADE_PLUGIN_PERMISSION_ID(),
            where: address(p.plugin),
            who: here,
            operation: _grantOrRevoke,
            condition: PermissionLib.NO_CONDITION
        });

        permissions[3] = PermissionLib.MultiTargetPermission({
            permissionId: p.clock.CLOCK_ADMIN_ROLE(),
            where: address(p.clock),
            who: here,
            operation: _grantOrRevoke,
            condition: PermissionLib.NO_CONDITION
        });

        permissions[4] = PermissionLib.MultiTargetPermission({
            permissionId: p.nftLock.LOCK_ADMIN_ROLE(),
            where: address(p.nftLock),
            who: here,
            operation: _grantOrRevoke,
            condition: PermissionLib.NO_CONDITION
        });

        permissions[5] = PermissionLib.MultiTargetPermission({
            permissionId: p.votingEscrow.PAUSER_ROLE(),
            where: address(p.votingEscrow),
            who: here,
            operation: _grantOrRevoke,
            condition: PermissionLib.NO_CONDITION
        });

        return permissions;
    }

    function getOldDeployment() public view returns (DeploymentV1_0_0 memory) {
        return IFactory(factory).getDeployment();
    }

    function getDeployment() public view returns (Deployment memory) {
        return deployment;
    }
}
