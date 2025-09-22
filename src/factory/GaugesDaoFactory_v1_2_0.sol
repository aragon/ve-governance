// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {DAOFactory} from "@aragon/osx/framework/dao/DAOFactory.sol";
import {IWithdrawalQueueErrors} from "@escrow/IVotingEscrowIncreasing.sol";
import {IAddressGaugeVote as IGaugeVote} from "@voting/IAddressGaugeVoter.sol";
import {Action} from "@aragon/osx-commons-contracts/src/executors/IExecutor.sol";
import {PermissionManager} from "@aragon/osx/core/permission/PermissionManager.sol";

import {
    VotingEscrow,
    Clock,
    Lock,
    Curve,
    ExitQueue,
    GaugeVoter,
    GaugeVoterSetupV1_2_0 as GaugeVoterSetup,
    IGaugeVoterSetupParams
} from "@setup/GaugeVoterSetup_v1_2_0.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {
    hashHelpers,
    PluginSetupRef
} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import {IPlugin} from "@aragon/osx-commons-contracts/src/plugin/IPlugin.sol";
import {Multisig} from "@aragon/multisig/src/Multisig.sol";
import {MultisigSetup as MultisigPluginSetup} from "@aragon/multisig/src/MultisigSetup.sol";
import {ProxyLib} from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import {EscrowIVotesAdapter} from "@delegation/EscrowIVotesAdapter.sol";

/// @notice The struct containing all the parameters to deploy the DAO
/// @param minApprovals The amount of approvals required for the multisig to be able to execute a proposal on the DAO
/// @param multisigMembers The list of addresses to be defined as the initial multisig signers
/// @param tokenParameters A list with the tokens and metadata for which a plugin and a VE should be deployed
/// @param feePercent The fee taken on withdrawals (1 ether = 100%)
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
    bytes multisigMetadata;
    // Gauge Voter
    TokenParameters[] tokenParameters;
    uint16 feePercent;
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
    GaugeVoter plugin;
    Curve curve;
    ExitQueue exitQueue;
    VotingEscrow votingEscrow;
    Clock clock;
    Lock nftLock;
    EscrowIVotesAdapter delegationAdapter;
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

/// @notice A singleton contract designed to run the deployment once and become a read-only store of the contracts deployed
contract GaugesDaoFactoryV1_2_0 {
    using ProxyLib for address;

    function version() external pure returns (string memory) {
        return "1.2.0";
    }

    /// @notice Thrown when attempting to call deployOnce() when the DAO is already deployed.
    error AlreadyDeployed();

    DeploymentParameters parameters;
    Deployment deployment;

    /// @notice Initializes the factory and performs the full deployment. Values become read-only after that.
    /// @param _parameters The parameters of the one-time deployment.
    constructor(DeploymentParameters memory _parameters) {
        parameters.minApprovals = _parameters.minApprovals;
        parameters.multisigMembers = _parameters.multisigMembers;
        parameters.multisigMetadata = _parameters.multisigMetadata;

        for (uint i = 0; i < _parameters.tokenParameters.length; ) {
            parameters.tokenParameters.push(_parameters.tokenParameters[i]);

            unchecked {
                i++;
            }
        }

        parameters.minDeposit = _parameters.minDeposit;
        parameters.feePercent = _parameters.feePercent;
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

            PluginRepo pluginRepo = prepareGaugeVoterPluginRepo(dao);

            for (uint i = 0; i < parameters.tokenParameters.length; ) {
                (
                    pluginSet,
                    deployment.gaugeVoterPluginRepo,
                    preparedVoterSetupData
                ) = prepareGaugeVoterPlugin(
                    dao,
                    parameters.tokenParameters[i],
                    pluginRepo,
                    repoTag
                );

                deployment.gaugeVoterPluginSets.push(pluginSet);

                applyPluginInstallation(
                    dao,
                    address(pluginSet.plugin),
                    deployment.gaugeVoterPluginRepo,
                    repoTag,
                    preparedVoterSetupData
                );

                activateGaugeVoterInstallation(dao, pluginSet);

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
        DAOFactory.DAOSettings memory daoSettings = DAOFactory.DAOSettings({
            trustedForwarder: address(0),
            daoURI: "",
            subdomain: "some-test-subdomain",
            metadata: ""
        });

        (dao, ) = DAOFactory(parameters.osxDaoFactory).createDao(
            daoSettings,
            new DAOFactory.PluginSettings[](0)
        );

        Action[] memory actions = new Action[](1);
        actions[0].to = address(dao);
        actions[0].data = abi.encodeCall(PermissionManager.grant, (address(dao), address(this), dao.ROOT_PERMISSION_ID()));
        dao.execute(bytes32(0), actions, 0);
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
            ),
            IPlugin.TargetConfig({target: address(dao), operation: IPlugin.Operation.Call}),
            parameters.multisigMetadata
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

    function prepareGaugeVoterPluginRepo(DAO dao) internal returns (PluginRepo pluginRepo) {
        // Publish repo
        pluginRepo = PluginRepoFactory(parameters.pluginRepoFactory)
            .createPluginRepoWithFirstVersion(
                parameters.voterEnsSubdomain,
                address(parameters.voterPluginSetup),
                address(dao),
                " ",
                " "
            );
    }

    function prepareGaugeVoterPlugin(
        DAO dao,
        TokenParameters memory tokenParameters,
        PluginRepo pluginRepo,
        PluginRepo.Tag memory repoTag
    ) internal returns (GaugePluginSet memory, PluginRepo, IPluginSetup.PreparedSetupData memory) {
        // Plugin settings
        bytes memory settingsData = parameters.voterPluginSetup.encodeSetupData(
            IGaugeVoterSetupParams({
                isPaused: parameters.votingPaused,
                token: tokenParameters.token,
                veTokenName: tokenParameters.veTokenName,
                veTokenSymbol: tokenParameters.veTokenSymbol,
                feePercent: parameters.feePercent,
                cooldown: parameters.cooldownPeriod,
                minLock: parameters.minLockDuration,
                minDeposit: parameters.minDeposit
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
            plugin: GaugeVoter(plugin),
            curve: Curve(helpers[0]),
            exitQueue: ExitQueue(helpers[1]),
            votingEscrow: VotingEscrow(helpers[2]),
            clock: Clock(helpers[3]),
            nftLock: Lock(helpers[4]),
            delegationAdapter: EscrowIVotesAdapter(helpers[5])
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

    function activateGaugeVoterInstallation(DAO dao, GaugePluginSet memory pluginSet) internal {
        dao.grant(
            address(pluginSet.votingEscrow),
            address(this),
            pluginSet.votingEscrow.ESCROW_ADMIN_ROLE()
        );

        pluginSet.votingEscrow.setCurve(address(pluginSet.curve));
        pluginSet.votingEscrow.setQueue(address(pluginSet.exitQueue));
        pluginSet.votingEscrow.setVoter(address(pluginSet.plugin));
        pluginSet.votingEscrow.setLockNFT(address(pluginSet.nftLock));
        pluginSet.votingEscrow.setIVotesAdapter(address(pluginSet.delegationAdapter));
        dao.revoke(
            address(pluginSet.votingEscrow),
            address(this),
            pluginSet.votingEscrow.ESCROW_ADMIN_ROLE()
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
        dao.revoke(address(dao), address(this), dao.EXECUTE_PERMISSION_ID());
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
