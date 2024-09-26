// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {DAOFactory} from "@aragon/osx/framework/dao/DAOFactory.sol";
import {Clock} from "@clock/Clock.sol";
import {IEscrowCurveUserStorage} from "@escrow-interfaces/IEscrowCurveIncreasing.sol";
import {IWithdrawalQueueErrors} from "src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol";
import {IGaugeVote} from "src/voting/ISimpleGaugeVoter.sol";
import {VotingEscrow, Clock, Lock, QuadraticIncreasingEscrow, ExitQueue, SimpleGaugeVoter, SimpleGaugeVoterSetup, ISimpleGaugeVoterSetupParams} from "src/voting/SimpleGaugeVoterSetup.sol";
import {Addresslist} from "@aragon/osx/plugins/utils/Addresslist.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {hashHelpers, PluginSetupRef} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {IPluginSetup} from "@aragon/osx/framework/plugin/setup/IPluginSetup.sol";
import {Multisig} from "@aragon/osx/plugins/governance/multisig/Multisig.sol";
import {MultisigSetup as MultisigPluginSetup} from "@aragon/osx/plugins/governance/multisig/MultisigSetup.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {GovernanceERC20} from "@aragon/osx/token/ERC20/governance/GovernanceERC20.sol";
import {createERC1967Proxy} from "@aragon/osx/utils/Proxy.sol";
import {PermissionLib} from "@aragon/osx/core/permission/PermissionLib.sol";

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
    uint256 feePercent;
    uint64 warmupPeriod;
    uint64 cooldownPeriod;
    uint64 minLockDuration;
    bool votingPaused;
    // Voter plugin setup and ENS
    PluginRepo multisigPluginRepo;
    uint8 multisigPluginRelease;
    uint16 multisigPluginBuild;
    SimpleGaugeVoterSetup voterPluginSetup;
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
    SimpleGaugeVoter plugin;
    QuadraticIncreasingEscrow curve;
    ExitQueue exitQueue;
    VotingEscrow votingEscrow;
    Clock clock;
    Lock nftLock;
}

/// @notice Contains the artifacts that resulted from running a deployment
struct Deployment {
    DAO dao;
    // Plugins
    Multisig multisigPlugin;
    GaugePluginSet[] gaugePluginSets;
    // Plugin repo's
    PluginRepo voterPluginRepo;
}

/// @notice A singleton contract designed to run the deployment once and become a read-only store of the contracts deployed
contract GaugesDaoFactory {
    /// @notice Thrown when attempting to call deployOnce() when the DAO is already deployed.
    error AlreadyDeployed();

    DeploymentParameters parameters;
    Deployment deployment;

    /// @dev Solidity doesn't allow to store a struct array on a storage struct. Storing a reference to link from parameters.tokenParameters
    TokenParameters[] private storageTokenParams;

    /// @notice Initializes the factory and performs the full deployment. Values become read-only after that.
    /// @param _parameters The parameters of the one-time deployment.
    constructor(DeploymentParameters memory _parameters) {
        parameters.minApprovals = _parameters.minApprovals;
        parameters.multisigMembers = _parameters.multisigMembers;

        for (uint i = 0; i < _parameters.tokenParameters.length; ) {
            storageTokenParams.push(_parameters.tokenParameters[i]);

            unchecked {
                i++;
            }
        }
        parameters.tokenParameters = storageTokenParams;

        parameters.feePercent = _parameters.feePercent;
        parameters.warmupPeriod = _parameters.warmupPeriod;
        parameters.cooldownPeriod = _parameters.cooldownPeriod;
        parameters.minLockDuration = _parameters.minLockDuration;
        parameters.votingPaused = _parameters.votingPaused;
        parameters.multisigPluginRepo = _parameters.multisigPluginRepo;
        parameters.multisigPluginRelease = _parameters.multisigPluginRelease;
        parameters.multisigPluginBuild = _parameters.multisigPluginBuild;
        parameters.voterPluginSetup = _parameters.voterPluginSetup;
        parameters.voterEnsSubdomain = _parameters.voterEnsSubdomain;
        parameters.osxDaoFactory = _parameters.osxDaoFactory;
        parameters.pluginSetupProcessor = _parameters.pluginSetupProcessor;
        parameters.pluginRepoFactory = _parameters.pluginRepoFactory;
    }

    /// @notice Run the deployment and store the artifacts in a read-only store that can be retrieved via `getDeployment()` and `getDeploymentParameters()`
    function deployOnce() public {
        if (address(deployment.dao) != address(0)) revert AlreadyDeployed();

        // Deploy the DAO (this contract is the interim owner)
        DAO dao = prepareDao();
        deployment.dao = dao;

        // Deploy and install the plugins

        grantApplyInstallationPermissions(dao);

        // MULTISIG
        {
            IPluginSetup.PreparedSetupData memory preparedMultisigSetupData;

            PluginRepo.Tag memory repoTag = PluginRepo.Tag(
                parameters.multisigPluginRelease,
                parameters.multisigPluginBuild
            );

            (deployment.multisigPlugin, preparedMultisigSetupData) = prepareMultisig(dao, repoTag);

            applyPluginInstallation(
                dao,
                address(deployment.multisigPlugin),
                parameters.multisigPluginRepo,
                repoTag,
                preparedMultisigSetupData
            );
        }

        // GAUGE VOTER(s)
        {
            IPluginSetup.PreparedSetupData memory preparedVoterSetupData;

            PluginRepo.Tag memory repoTag = PluginRepo.Tag(1, 1);
            GaugePluginSet memory pluginSet;

            for (uint i = 0; i < parameters.tokenParameters.length; ) {
                (
                    pluginSet,
                    deployment.voterPluginRepo,
                    preparedVoterSetupData
                ) = prepareSimpleGaugeVoterPlugin(dao, parameters.tokenParameters[i], repoTag);

                deployment.gaugePluginSets.push(pluginSet);

                applyPluginInstallation(
                    dao,
                    address(pluginSet.plugin),
                    deployment.voterPluginRepo,
                    repoTag,
                    preparedVoterSetupData
                );

                unchecked {
                    i++;
                }
            }
        }

        // Clean up
        revokeApplyInstallationPermissions(dao);

        // Remove this contract as owner
        revokeOwnerPermission(deployment.dao);
    }

    function prepareDao() internal returns (DAO dao) {
        address daoBase = DAOFactory(parameters.osxDaoFactory).daoBase();

        dao = DAO(
            payable(
                createERC1967Proxy(
                    address(daoBase),
                    abi.encodeCall(
                        DAO.initialize,
                        (
                            "", // Metadata URI
                            address(this), // initialOwner
                            address(0x0), // Trusted forwarder
                            "" // DAO URI
                        )
                    )
                )
            )
        );

        // Grant DAO all the needed permissions on itself
        PermissionLib.SingleTargetPermission[]
            memory items = new PermissionLib.SingleTargetPermission[](3);
        items[0] = PermissionLib.SingleTargetPermission(
            PermissionLib.Operation.Grant,
            address(dao),
            dao.ROOT_PERMISSION_ID()
        );
        items[1] = PermissionLib.SingleTargetPermission(
            PermissionLib.Operation.Grant,
            address(dao),
            dao.UPGRADE_DAO_PERMISSION_ID()
        );
        items[2] = PermissionLib.SingleTargetPermission(
            PermissionLib.Operation.Grant,
            address(dao),
            dao.REGISTER_STANDARD_CALLBACK_PERMISSION_ID()
        );

        dao.applySingleTargetPermissions(address(dao), items);
    }

    function prepareMultisig(
        DAO dao,
        PluginRepo.Tag memory repoTag
    ) internal returns (Multisig, IPluginSetup.PreparedSetupData memory) {
        bytes memory settingsData = abi.encode(
            parameters.multisigMembers,
            Multisig.MultisigSettings(
                true, // onlyListed
                parameters.minApprovals
            )
        );

        (address plugin, IPluginSetup.PreparedSetupData memory preparedSetupData) = parameters
            .pluginSetupProcessor
            .prepareInstallation(
                address(dao),
                PluginSetupProcessor.PrepareInstallationParams(
                    PluginSetupRef(repoTag, parameters.multisigPluginRepo),
                    settingsData
                )
            );

        return (Multisig(plugin), preparedSetupData);
    }

    function prepareSimpleGaugeVoterPlugin(
        DAO dao,
        TokenParameters memory tokenParameters,
        PluginRepo.Tag memory repoTag
    ) internal returns (GaugePluginSet memory, PluginRepo, IPluginSetup.PreparedSetupData memory) {
        // Publish repo
        PluginRepo pluginRepo = PluginRepoFactory(parameters.pluginRepoFactory)
            .createPluginRepoWithFirstVersion(
                parameters.voterEnsSubdomain,
                address(parameters.voterPluginSetup),
                address(dao),
                " ",
                " "
            );

        // Plugin settings
        bytes memory settingsData = parameters.voterPluginSetup.encodeSetupData(
            ISimpleGaugeVoterSetupParams({
                isPaused: parameters.votingPaused,
                token: tokenParameters.token,
                veTokenName: tokenParameters.veTokenName,
                veTokenSymbol: tokenParameters.veTokenSymbol,
                feePercent: parameters.feePercent,
                warmup: parameters.warmupPeriod,
                cooldown: parameters.cooldownPeriod,
                minLock: parameters.minLockDuration
            })
        );

        (address plugin, IPluginSetup.PreparedSetupData memory preparedSetupData) = parameters
            .pluginSetupProcessor
            .prepareInstallation(
                address(dao),
                PluginSetupProcessor.PrepareInstallationParams(
                    PluginSetupRef(repoTag, pluginRepo),
                    settingsData
                )
            );

        address[] memory helpers = preparedSetupData.helpers;
        GaugePluginSet memory pluginSet = GaugePluginSet({
            plugin: SimpleGaugeVoter(plugin),
            curve: QuadraticIncreasingEscrow(helpers[0]),
            exitQueue: ExitQueue(helpers[1]),
            votingEscrow: VotingEscrow(helpers[2]),
            clock: Clock(helpers[3]),
            nftLock: Lock(helpers[4])
        });

        return (pluginSet, pluginRepo, preparedSetupData);
    }

    function applyPluginInstallation(
        DAO dao,
        address plugin,
        PluginRepo pluginRepo,
        PluginRepo.Tag memory pluginRepoTag,
        IPluginSetup.PreparedSetupData memory preparedSetupData
    ) internal {
        parameters.pluginSetupProcessor.applyInstallation(
            address(dao),
            PluginSetupProcessor.ApplyInstallationParams(
                PluginSetupRef(pluginRepoTag, pluginRepo),
                plugin,
                preparedSetupData.permissions,
                hashHelpers(preparedSetupData.helpers)
            )
        );
    }

    function grantApplyInstallationPermissions(DAO dao) internal {
        // The PSP can manage permissions on the new DAO
        dao.grant(address(dao), address(parameters.pluginSetupProcessor), dao.ROOT_PERMISSION_ID());

        // This factory can call applyInstallation() on the PSP
        dao.grant(
            address(parameters.pluginSetupProcessor),
            address(this),
            parameters.pluginSetupProcessor.APPLY_INSTALLATION_PERMISSION_ID()
        );
    }

    function revokeApplyInstallationPermissions(DAO dao) internal {
        // Revoking the permission for the factory to call applyInstallation() on the PSP
        dao.revoke(
            address(parameters.pluginSetupProcessor),
            address(this),
            parameters.pluginSetupProcessor.APPLY_INSTALLATION_PERMISSION_ID()
        );

        // Revoke the PSP permission to manage permissions on the new DAO
        dao.revoke(
            address(dao),
            address(parameters.pluginSetupProcessor),
            dao.ROOT_PERMISSION_ID()
        );
    }

    function revokeOwnerPermission(DAO dao) internal {
        dao.revoke(address(dao), address(this), dao.ROOT_PERMISSION_ID());
    }

    // Getters

    function getDeploymentParameters() public view returns (DeploymentParameters memory) {
        return parameters;
    }

    function getDeployment() public view returns (Deployment memory) {
        return deployment;
    }
}
