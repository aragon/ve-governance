// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "test/constants.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginRepoRegistry} from "@aragon/osx/framework/plugin/repo/PluginRepoRegistry.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {Addresslist} from "@aragon/osx/plugins/utils/Addresslist.sol";
import {IPluginSetup} from "@aragon/osx/framework/plugin/setup/IPluginSetup.sol";
import {PermissionLib} from "@aragon/osx/core/permission/PermissionLib.sol";
import {
    Multisig,
    MultisigSetup as MultisigPluginSetup
} from "@aragon/osx/plugins/governance/multisig/MultisigSetup.sol";
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
    Clock as ClockSeason,
    Curve as QuadraticIncreasingCurveSeason,
    GaugeVoter as TokenGaugeVoterSeason,
    GaugeVoterSetupSeason,
    IGaugeVoterSetupParams as IGaugeVoterSetupParamsSeason
} from "@setup/GaugeVoterSetupSeason.sol";

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {ProxyLib} from "@libs/ProxyLib.sol";

import {Upgrades} from "@foundry-upgrades/LegacyUpgrades.sol";
import {Options} from "@foundry-upgrades/Options.sol";

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
    TokenGaugeVoterSeason plugin;
    QuadraticIncreasingCurveSeason curve;
    ExitQueue exitQueue;
    VotingEscrow votingEscrow;
    ClockSeason clock;
    Lock nftLock;
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

contract UpgradeGaugesFactoryV1_0_0__Season {
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
            newPluginSet.plugin = TokenGaugeVoterSeason(address(oldPluginSet.plugin));
            newPluginSet.curve = QuadraticIncreasingCurveSeason(address(oldPluginSet.curve));
            newPluginSet.votingEscrow = oldPluginSet.votingEscrow;
            newPluginSet.clock = ClockSeason(address(oldPluginSet.clock));
            newPluginSet.nftLock = oldPluginSet.nftLock;
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
        Upgrades.validateUpgrade("ClockSeason.sol:ClockSeason", options);

        options.referenceContract = "QuadraticIncreasingCurve.sol:QuadraticIncreasingEscrow";
        Upgrades.validateUpgrade(
            "QuadraticIncreasingCurveSeason.sol:QuadraticIncreasingCurveSeason",
            options
        );

        // SimpleGaugeVoter can't be upgraded due to slot incompatibilities. Should always be a new deployment
        //options.referenceContract = "TokenGaugeVoter.sol:TokenGaugeVoter";
        //Upgrades.validateUpgrade("TokenGaugeVoterSeason.sol:TokenGaugeVoterSeason", options);
    }

    function upgrade(
        bool validate,
        ClockSeason clockUpgrade,
        QuadraticIncreasingCurveSeason curveUpgrade,
        TokenGaugeVoterSeason tokenGaugeVoterUpgrade
    ) public {
        if (validate) {
            validateUpgrade();

            for (uint i = 0; i < parameters.tokenParameters.length; i++) {
                GaugePluginSet memory pluginSet = deployment.gaugeVoterPluginSets[i];
                // make sure that we are using the same constants
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
                require(
                    CurveConstantLib.SHARED_QUADRATIC_COEFFICIENT == coefficients[2],
                    "invalid quadratic coefficient"
                );
            }
        }

        _deployTokenGaugeVoterSeason(address(tokenGaugeVoterUpgrade));

        _upgradeContracts(clockUpgrade, curveUpgrade);

        // deploy an address gauge voter that must be used on the upgraded escrow contract.

        // set the gauge new token voter on the escrow
        _setTokenGaugeVoterSeason();
    }

    ////////////////////////////////////////////////
    ///-------------- Internal ------------------///
    ////////////////////////////////////////////////

    function _upgradeContracts(
        ClockSeason clockUpgrade,
        QuadraticIncreasingCurveSeason curveUpgrade
    ) internal {
        for (uint i = 0; i < parameters.tokenParameters.length; i++) {
            GaugePluginSet memory pluginSet = deployment.gaugeVoterPluginSets[i];

            pluginSet.clock.upgradeTo(address(clockUpgrade));
            pluginSet.curve.upgradeTo(address(curveUpgrade));

            // We only need to pause escrow as other contracts' state changing
            // functions can only be called by escrow.
            pluginSet.votingEscrow.pause();
        }
    }

    function _deployTokenGaugeVoterSeason(address _base) internal {
        bool startPaused = true;

        for (uint i = 0; i < deployment.gaugeVoterPluginSets.length; i++) {
            address plugin = _base.deployUUPSProxy(
                abi.encodeCall(
                    TokenGaugeVoterSeason.initialize,
                    (
                        address(deployment.dao),
                        address(deployment.gaugeVoterPluginSets[i].votingEscrow),
                        startPaused,
                        address(deployment.gaugeVoterPluginSets[i].clock)
                    )
                )
            );
            deployment.gaugeVoterPluginSets[i].plugin = TokenGaugeVoterSeason(plugin);
        }
    }

    function _setTokenGaugeVoterSeason() internal {
        // set the address gauge voter on the escrow
        for (uint i = 0; i < deployment.gaugeVoterPluginSets.length; i++) {
            TokenGaugeVoterSeason tokenGaugeVoter = deployment.gaugeVoterPluginSets[i].plugin;
            VotingEscrow votingEscrow = deployment.gaugeVoterPluginSets[i].votingEscrow;

            votingEscrow.setVoter(address(tokenGaugeVoter));
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
