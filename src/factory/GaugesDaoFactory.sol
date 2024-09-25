// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {DAOFactory} from "@aragon/osx/framework/dao/DAOFactory.sol";
import {Clock} from "@clock/Clock.sol";
import {IEscrowCurveUserStorage} from "@escrow-interfaces/IEscrowCurveIncreasing.sol";
import {IWithdrawalQueueErrors} from "src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol";
import {IGaugeVote} from "src/voting/ISimpleGaugeVoter.sol";
import {SimpleGaugeVoter, SimpleGaugeVoterSetup, ISimpleGaugeVoterSetupParams} from "src/voting/SimpleGaugeVoterSetup.sol";
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
/// @param token1Address The address of the IVotes compatible ERC20 token contract to use for the voting power
/// @param token2Address The address of the IVotes compatible ERC20 token contract to use for the voting power
/// @param minApprovals The amount of approvals required for the multisig to be able to execute a proposal on the DAO
// OSx
/// @param osxDaoFactory The address of the OSx DAO factory contract, used to retrieve the DAO implementation address
/// @param pluginSetupProcessor The address of the OSx PluginSetupProcessor contract on the target chain
/// @param pluginRepoFactory The address of the OSx PluginRepoFactory contract on the target chain
// Plugins
/// @param multisigPluginSetup The address of the already deployed plugin setup for the standard multisig
/// @param votingPluginSetup The address of the already deployed plugin setup for the optimistic voting plugin
/// @param multisigMembers The list of addresses to be defined as the initial multisig signers
/// @param multisigEnsDomain The subdomain to use as the ENS for the standard mulsitig plugin setup. Note: it must be unique and available.
/// @param votingEnsDomain The subdomain to use as the ENS for the optimistic voting plugin setup. Note: it must be unique and available.
struct DeploymentParameters {
    // Multisig settings
    uint64 minProposalDuration;
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

struct Deployment {
    DAO dao;
    // Plugins
    Multisig multisigPlugin;
    SimpleGaugeVoter[] voterPlugins;
    // Plugin repo's
    PluginRepo voterPluginRepo;
}

contract GaugesDaoFactory {
    /// @notice Thrown when attempting to call deployOnce() when the DAO is already deployed.
    error AlreadyDeployed();

    DeploymentParameters parameters;
    Deployment deployment;

    /// @notice Initializes the factory and performs the full deployment. Values become read-only after that.
    /// @param _parameters The parameters of the one-time deployment.
    constructor(DeploymentParameters memory _parameters) {
        parameters = _parameters;
    }

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
            SimpleGaugeVoter voterPlugin;

            PluginRepo.Tag memory repoTag = PluginRepo.Tag(1, 1);

            deployment.voterPlugins = new SimpleGaugeVoter[](parameters.tokenParameters.length);

            for (uint i = 0; i < parameters.tokenParameters.length; ) {
                (
                    voterPlugin,
                    deployment.voterPluginRepo,
                    preparedVoterSetupData
                ) = prepareSimpleGaugeVoterPlugin(dao, parameters.tokenParameters[i], repoTag);

                applyPluginInstallation(
                    dao,
                    address(voterPlugin),
                    deployment.voterPluginRepo,
                    repoTag,
                    preparedVoterSetupData
                );

                deployment.voterPlugins[i] = voterPlugin;

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
    ) internal returns (SimpleGaugeVoter, PluginRepo, IPluginSetup.PreparedSetupData memory) {
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
        return (SimpleGaugeVoter(plugin), pluginRepo, preparedSetupData);
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
