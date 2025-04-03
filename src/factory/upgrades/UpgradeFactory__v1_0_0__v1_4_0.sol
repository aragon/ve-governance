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
import {Multisig, MultisigSetup as MultisigPluginSetup} from "@aragon/osx/plugins/governance/multisig/MultisigSetup.sol";
import {hashHelpers, PluginSetupRef} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";

import {SimpleGaugeVoterSetup, VotingEscrow, Clock, Lock, QuadraticIncreasingEscrow, ExitQueue, SimpleGaugeVoter, ISimpleGaugeVoterSetupParams} from "@setup/SimpleGaugeVoterSetup.sol";
import {GaugesDaoFactory, Deployment as DeploymentV1_0_0, DeploymentParameters as DeploymentParametersV1_0_0, GaugePluginSet as GaugePluginSetV1_0_0} from "../GaugesDaoFactory.sol";

import {Clock as ClockV1_4_0, QuadraticIncreasingEscrow as LinearIncreasingCurve, SimpleGaugeVoter as SimpleGaugeVoterV1_1_0, VotingEscrow as VotingEscrowV1_4_0, SimpleGaugeVoterSetupV1_4_0, ISimpleGaugeVoterSetupParams as ISimpleGaugeVoterSetupParamsV1_4_0} from "@setup/SimpleGaugeVoterSetup_v1_4_0.sol";

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {ProxyLib} from "@libs/ProxyLib.sol";

import {Upgrades} from "@foundry-upgrades/LegacyUpgrades.sol";
import {Options} from "@foundry-upgrades/Options.sol";

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
    SimpleGaugeVoterSetupV1_4_0 voterPluginSetup;
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
    SimpleGaugeVoterV1_1_0 plugin;
    LinearIncreasingCurve curve;
    ExitQueue exitQueue;
    VotingEscrowV1_4_0 votingEscrow;
    ClockV1_4_0 clock;
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

contract UpgradeGaugesFactoryV1_0_0__V1_4_0 {
    using Address for address;
    using Clones for address;
    using ERC165Checker for address;
    using ProxyLib for address;

    address factory;

    // PluginRepoFactory pluginRepoFactory;
    // // PluginRepo oldPluginRepo;
    // PluginSetupProcessor pluginSetupProcessor;

    Deployment deployment;
    DeploymentParameters parameters;
    // Deployment oldDeployment;

    constructor(
        address _factory,
        SimpleGaugeVoterSetupV1_4_0 _voterPluginSetupUpgrade,
        string memory _voterEnsSubdomain
    ) {
        factory = _factory;

        DeploymentV1_0_0 memory oldDeployment = IFactory(factory).getDeployment();

        // init with the old contracts, as needed we will overwrite
        for (uint i = 0; i < oldDeployment.gaugeVoterPluginSets.length; i++) {
            GaugePluginSetV1_0_0 memory oldPluginSet = oldDeployment.gaugeVoterPluginSets[i];

            GaugePluginSet memory newPluginSet;

            // copy the non-changing versions over
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

        // add the new setup contract
        parameters.voterPluginSetup = _voterPluginSetupUpgrade;
        parameters.voterEnsSubdomain = _voterEnsSubdomain;
    }

    function validateUpgrade() public {
        Options memory options;

        string[] memory exclude = new string[](1);
        // disable initializers is invoked but the custom unsafe allow option is not set in the natspec
        exclude[0] = "lib/osx/packages/contracts/src/core/plugin/PluginUUPSUpgradeable.sol";
        options.exclude = exclude;

        // SimpleGaugeVoter can't be upgraded due to slot incompatibilities. Should always be a new deployment
        //options.referenceContract = "SimpleGaugeVoter_v1_1_0.sol";
        //Upgrades.validateUpgrade("SimpleGaugeVoter_v1_2_0.sol:SimpleGaugeVoterV1_2_0", options);

        options.referenceContract = "Clock.sol";
        Upgrades.validateUpgrade("Clock_v1_4_0.sol:ClockV1_4_0", options);

        options.referenceContract = "QuadraticIncreasingEscrow.sol";
        Upgrades.validateUpgrade("LinearIncreasingEscrow:LinearIncreasingCurve", options);
    }

    function upgrade() public {
        _upgradeContracts();
    }

    ////////////////////////////////////////////////
    ///-------------- Internal ------------------///
    ////////////////////////////////////////////////

    function _upgradeContracts() internal {
        PluginSetupProcessor pluginSetupProcessor = parameters.pluginSetupProcessor;
        DAO dao = deployment.dao;
        // Get Permission IDs
        bytes32 rootPermissionID = dao.ROOT_PERMISSION_ID();
        bytes32 applyInstallationPermissionID = pluginSetupProcessor
            .APPLY_INSTALLATION_PERMISSION_ID();
        bytes32 applyUninstallationPermissionID = pluginSetupProcessor
            .APPLY_UNINSTALLATION_PERMISSION_ID();

        // Grant the temporary permissions.
        // Grant Temporarly `ROOT_PERMISSION` to `pluginSetupProcessor`.
        dao.grant(address(dao), address(pluginSetupProcessor), rootPermissionID);

        // Grant Temporarly `APPLY_INSTALLATION_PERMISSION` on `pluginSetupProcessor` to this `DAOFactory`.
        dao.grant(address(pluginSetupProcessor), address(this), applyInstallationPermissionID);

        // Grant Temporarly `APPLY_UNINSTALLATION_PERMISSION` on `pluginSetupProcessor` to this `DAOFactory`.
        dao.grant(address(pluginSetupProcessor), address(this), applyUninstallationPermissionID);

        ClockV1_4_0 clockUpgrade = new ClockV1_4_0();
        LinearIncreasingCurve curveUpgrade = new LinearIncreasingCurve();

        for (uint i = 0; i < parameters.tokenParameters.length; i++) {
            GaugePluginSet memory pluginSet = deployment.gaugeVoterPluginSets[i];

            pluginSet.clock.upgradeTo(address(clockUpgrade));
            pluginSet.curve.upgradeTo(address(curveUpgrade));

            // Publish repo
            PluginRepo pluginRepo = PluginRepoFactory(parameters.pluginRepoFactory)
                .createPluginRepoWithFirstVersion(
                    parameters.voterEnsSubdomain,
                    address(parameters.voterPluginSetup),
                    address(dao),
                    " ",
                    " "
                );

            PluginRepo.Tag memory repoTag = PluginRepo.Tag(1, 1);

            // Prepare old plugin for uninstallation
            PermissionLib.MultiTargetPermission[] memory permissions = preparePluginUninstallation(
                deployment.gaugeVoterPluginRepo,
                repoTag,
                pluginSet
            );

            applyPluginUninstallation(
                address(pluginSet.plugin),
                deployment.gaugeVoterPluginRepo,
                repoTag,
                permissions
            );

            // Prepare and apply plugin
            GaugePluginSet memory newPluginSet;
            IPluginSetup.PreparedSetupData memory preparedVoterSetupData;

            // Prepare plugin
            (newPluginSet, preparedVoterSetupData) = preparePluginInstallation(
                parameters.tokenParameters[i],
                pluginRepo,
                repoTag,
                parameters.pluginSetupProcessor
            );

            applyPluginInstallation(
                address(newPluginSet.plugin),
                pluginRepo,
                repoTag,
                preparedVoterSetupData
            );

            deployment.gaugeVoterPluginSets.push(newPluginSet);

            // Activate the plugin
            updateSimpleGaugeVoterInstallation(newPluginSet);
        }

        // Revoke the temporary permissions.
        // Revoke `ROOT_PERMISSION` from `pluginSetupProcessor`.
        dao.revoke(address(dao), address(pluginSetupProcessor), rootPermissionID);

        // Revoke `APPLY_INSTALLATION_PERMISSION` from `pluginSetupProcessor`.
        dao.revoke(address(pluginSetupProcessor), address(this), applyInstallationPermissionID);

        // Revoke `APPLY_UNINSTALLATION_PERMISSION` from `pluginSetupProcessor`.
        dao.revoke(address(pluginSetupProcessor), address(this), applyUninstallationPermissionID);
    }

    function preparePluginInstallation(
        TokenParameters memory tokenParameters,
        PluginRepo pluginRepo,
        PluginRepo.Tag memory repoTag,
        PluginSetupProcessor pluginSetupProcessor
    ) internal returns (GaugePluginSet memory, IPluginSetup.PreparedSetupData memory) {
        // Plugin settings
        bytes memory settingsData = parameters.voterPluginSetup.encodeSetupData(
            ISimpleGaugeVoterSetupParamsV1_4_0({
                isPaused: parameters.votingPaused,
                token: tokenParameters.token,
                veTokenName: tokenParameters.veTokenName,
                veTokenSymbol: tokenParameters.veTokenSymbol,
                feePercent: parameters.feePercent,
                warmup: parameters.warmupPeriod,
                cooldown: parameters.cooldownPeriod,
                minLock: parameters.minLockDuration,
                minDeposit: parameters.minDeposit
            })
        );

        (
            address plugin,
            IPluginSetup.PreparedSetupData memory preparedSetupData
        ) = pluginSetupProcessor.prepareInstallation(
                address(deployment.dao),
                PluginSetupProcessor.PrepareInstallationParams(
                    PluginSetupRef(repoTag, pluginRepo),
                    settingsData
                )
            );

        address[] memory helpers = preparedSetupData.helpers;
        GaugePluginSet memory pluginSet = GaugePluginSet({
            plugin: SimpleGaugeVoterV1_1_0(plugin),
            curve: LinearIncreasingCurve(helpers[0]),
            exitQueue: ExitQueue(helpers[1]),
            votingEscrow: VotingEscrowV1_4_0(helpers[2]),
            clock: ClockV1_4_0(helpers[3]),
            nftLock: Lock(helpers[4])
        });

        return (pluginSet, preparedSetupData);
    }

    function applyPluginInstallation(
        address plugin,
        PluginRepo pluginRepo,
        PluginRepo.Tag memory pluginRepoTag,
        IPluginSetup.PreparedSetupData memory preparedSetupData
    ) internal {
        parameters.pluginSetupProcessor.applyInstallation(
            address(deployment.dao),
            PluginSetupProcessor.ApplyInstallationParams(
                PluginSetupRef(pluginRepoTag, pluginRepo),
                plugin,
                preparedSetupData.permissions,
                hashHelpers(preparedSetupData.helpers)
            )
        );
    }

    function preparePluginUninstallation(
        PluginRepo pluginRepo,
        PluginRepo.Tag memory repoTag,
        GaugePluginSet memory pluginSet
    ) internal returns (PermissionLib.MultiTargetPermission[] memory permissions) {
        address[] memory helpers = new address[](5);
        helpers[0] = address(pluginSet.curve);
        helpers[1] = address(pluginSet.exitQueue);
        helpers[2] = address(pluginSet.votingEscrow);
        helpers[3] = address(pluginSet.clock);
        helpers[4] = address(pluginSet.nftLock);

        IPluginSetup.SetupPayload memory setupPayload = IPluginSetup.SetupPayload({
            plugin: address(pluginSet.plugin),
            currentHelpers: helpers,
            data: abi.encodePacked(uint256(0))
        });

        permissions = parameters.pluginSetupProcessor.prepareUninstallation(
            address(deployment.dao),
            PluginSetupProcessor.PrepareUninstallationParams(
                PluginSetupRef(repoTag, pluginRepo),
                setupPayload
            )
        );
    }

    function applyPluginUninstallation(
        address plugin,
        PluginRepo pluginRepo,
        PluginRepo.Tag memory pluginRepoTag,
        PermissionLib.MultiTargetPermission[] memory permissions
    ) internal {
        parameters.pluginSetupProcessor.applyUninstallation(
            address(deployment.dao),
            PluginSetupProcessor.ApplyUninstallationParams(
                plugin,
                PluginSetupRef(pluginRepoTag, pluginRepo),
                permissions
            )
        );
    }

    function updateSimpleGaugeVoterInstallation(GaugePluginSet memory pluginSet) internal {
        deployment.dao.grant(
            address(pluginSet.votingEscrow),
            address(this),
            pluginSet.votingEscrow.ESCROW_ADMIN_ROLE()
        );

        pluginSet.votingEscrow.setVoter(address(pluginSet.plugin));

        deployment.dao.revoke(
            address(pluginSet.votingEscrow),
            address(this),
            pluginSet.votingEscrow.ESCROW_ADMIN_ROLE()
        );
    }

    function getOldDeployment() public view returns (DeploymentV1_0_0 memory) {
        return IFactory(factory).getDeployment();
    }

    function getDeployment() public view returns (Deployment memory) {
        return deployment;
    }
}
