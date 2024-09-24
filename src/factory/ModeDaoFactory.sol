// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {DAOFactory} from "@aragon/osx/framework/dao/DAOFactory.sol";
import {Clock} from "@clock/Clock.sol";
import {IEscrowCurveUserStorage} from "@escrow-interfaces/IEscrowCurveIncreasing.sol";
import {IWithdrawalQueueErrors} from "src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol";
import {IGaugeVote} from "src/voting/ISimpleGaugeVoter.sol";
import {VotingEscrow, Lock, QuadraticIncreasingEscrow, ExitQueue, SimpleGaugeVoter, SimpleGaugeVoterSetup, ISimpleGaugeVoterSetupParams} from "src/voting/SimpleGaugeVoterSetup.sol";
import {Addresslist} from "@aragon/osx/plugins/utils/Addresslist.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {hashHelpers, PluginSetupRef} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {IPluginSetup} from "@aragon/osx/framework/plugin/setup/IPluginSetup.sol";
import {Multisig} from "@aragon/osx/plugins/governance/multisig/Multisig.sol";
import {MultisigSetup} from "@aragon/osx/plugins/governance/multisig/MultisigSetup.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {GovernanceERC20} from "@aragon/osx/token/ERC20/governance/GovernanceERC20.sol";
import {createERC1967Proxy} from "@aragon/osx/utils/Proxy.sol";
import {PermissionLib} from "@aragon/osx/core/permission/PermissionLib.sol";

contract ModeDaoFactory {
    /// @notice The struct containing all the parameters to deploy the DAO
    /// @param modeTokenAddress The address of the IVotes compatible ERC20 token contract to use for the voting power
    /// @param bptTokenAddress The address of the IVotes compatible ERC20 token contract to use for the voting power
    /// @param minApprovals The amount of approvals required for the multisig to be able to execute a proposal on the DAO
    // OSx
    /// @param osxDaoFactory The address of the OSx DAO factory contract, used to retrieve the DAO implementation address
    /// @param pluginSetupProcessor The address of the OSx PluginSetupProcessor contract on the target chain
    /// @param pluginRepoFactory The address of the OSx PluginRepoFactory contract on the target chain
    // Plugins
    /// @param multisigPluginSetup The address of the already deployed plugin setup for the standard multisig
    /// @param votingPluginSetup The address of the already deployed plugin setup for the optimistic voting plugin
    /// @param multisigMembers The list of addresses to be defined as the initial multisig signers
    /// @param multisigExpirationPeriod How many seconds until a pending multisig proposal expires
    /// @param multisigEnsDomain The subdomain to use as the ENS for the standard mulsitig plugin setup. Note: it must be unique and available.
    /// @param votingEnsDomain The subdomain to use as the ENS for the optimistic voting plugin setup. Note: it must be unique and available.
    struct DeploymentSettings {
        // Mode plugin settings
        IVotesUpgradeable tokenAddress;
        uint16 minApprovals;
        address[] multisigMembers;
        uint64 multisigExpirationPeriod;
        // OSx contracts
        address osxDaoFactory;
        PluginSetupProcessor pluginSetupProcessor;
        PluginRepoFactory pluginRepoFactory;
        // Main plugin setup
        SimpleGaugeVoterSetup voterPluginSetup;
        // ENS
        PluginRepo multisigPluginRepo;
        uint8 multisigPluginRepoRelease;
        uint16 multisigPluginRepoBuild;
        string voterEnsDomain;
    }

    struct Deployment {
        DAO dao;
        // Plugins
        Multisig multisigPlugin;
        SimpleGaugeVoter modeVoterPlugin;
        SimpleGaugeVoter bptVoterPlugin;
        // Plugin repo's
        PluginRepo voterPluginRepo;
    }

    /// @notice Thrown when attempting to call deployOnce() when the DAO is already deployed.
    error AlreadyDeployed();

    DeploymentSettings settings;
    Deployment deployment;

    /// @notice Initializes the factory and performs the full deployment. Values become read-only after that.
    /// @param _settings The settings of the one-time deployment.
    constructor(DeploymentSettings memory _settings) {
        settings = _settings;
    }

    function deployOnce() public {
        if (address(deployment.dao) != address(0)) revert AlreadyDeployed();

        IPluginSetup.PreparedSetupData memory preparedMultisigSetupData;
        IPluginSetup.PreparedSetupData memory preparedVoterSetupData;

        // DEPLOY THE DAO (The factory is the interim owner)
        DAO dao = prepareDao();
        deployment.dao = dao;

        // DEPLOY THE PLUGINS
        (
            deployment.multisigPlugin,
            deployment.multisigPluginRepo,
            preparedMultisigSetupData
        ) = prepareMultisig(dao);

        (
            deployment.voterPlugin,
            deployment.voterPluginRepo,
            preparedVoterSetupData
        ) = prepareSimpleGaugeVoterPlugin(dao);

        // APPLY THE INSTALLATIONS
        grantApplyInstallationPermissions(dao);

        applyPluginInstallation(
            dao,
            address(deployment.multisigPlugin),
            deployment.multisigPluginRepo,
            preparedMultisigSetupData
        );
        applyPluginInstallation(
            dao,
            address(deployment.voterPlugin),
            deployment.voterPluginRepo,
            preparedVoterSetupData
        );

        revokeApplyInstallationPermissions(dao);

        // REMOVE THIS CONTRACT AS OWNER
        revokeOwnerPermission(deployment.dao);

        // DEPLOY OTHER CONTRACTS
        deployment.publicKeyRegistry = deployPublicKeyRegistry();
    }

    function prepareDao() internal returns (DAO dao) {
        address daoBase = DAOFactory(settings.osxDaoFactory).daoBase();

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
        DAO dao
    ) internal returns (Multisig, PluginRepo, IPluginSetup.PreparedSetupData memory) {
        // Publish repo
        PluginRepo pluginRepo = PluginRepoFactory(settings.pluginRepoFactory)
            .createPluginRepoWithFirstVersion(
                settings.stdMultisigEnsDomain,
                address(settings.multisigPluginSetup),
                msg.sender,
                " ",
                " "
            );

        bytes memory settingsData = settings.multisigPluginSetup.encodeInstallationParameters(
            settings.multisigMembers,
            Multisig.MultisigSettings(
                true, // onlyListed
                settings.minApprovals,
                settings.multisigExpirationPeriod
            )
        );

        (address plugin, IPluginSetup.PreparedSetupData memory preparedSetupData) = settings
            .pluginSetupProcessor
            .prepareInstallation(
                address(dao),
                PluginSetupProcessor.PrepareInstallationParams(
                    PluginSetupRef(PluginRepo.Tag(1, 1), PluginRepo(pluginRepo)),
                    settingsData
                )
            );

        return (Multisig(plugin), pluginRepo, preparedSetupData);
    }

    function prepareSimpleGaugeVoterPlugin(
        DAO dao,
        address stdProposer,
        address emergencyProposer
    ) internal returns (SimpleGaugeVoter, PluginRepo, IPluginSetup.PreparedSetupData memory) {
        // Plugin settings
        bytes memory settingsData;
        {
            SimpleGaugeVoterSettings memory voterSettings = SimpleGaugeVoterSettings();
            // TODO

            SimpleGaugeVoterSetup.TokenSettings memory existingTokenSettings = SimpleGaugeVoterSetup
                .TokenSettings(address(settings.tokenAddress), "Mode", "TKO");
            GovernanceERC20.MintSettings memory unusedMintSettings = GovernanceERC20.MintSettings(
                new address[](0),
                new uint256[](0)
            );

            settingsData = settings.optimisticTokenVotingPluginSetup.encodeInstallationParams(
                SimpleGaugeVoterSetup.InstallationParameters(
                    voterSettings,
                    existingTokenSettings,
                    unusedMintSettings,
                    settings.modeL1ContractAddress,
                    settings.modeBridgeAddress,
                    settings.minStdProposalDuration,
                    stdProposer,
                    emergencyProposer
                )
            );
        }

        (address plugin, IPluginSetup.PreparedSetupData memory preparedSetupData) = settings
            .pluginSetupProcessor
            .prepareInstallation(
                address(dao),
                PluginSetupProcessor.PrepareInstallationParams(
                    PluginSetupRef(
                        PluginRepo.Tag(
                            settings.multisigPluginRepoRelease,
                            settings.multisigPluginRepoBuild,
                            2
                        ),
                        settings.multisigPluginRepo
                    ),
                    settingsData
                )
            );
        return (SimpleGaugeVoter(plugin), pluginRepo, preparedSetupData);
    }

    function applyPluginInstallation(
        DAO dao,
        address plugin,
        PluginRepo pluginRepo,
        IPluginSetup.PreparedSetupData memory preparedSetupData
    ) internal {
        settings.pluginSetupProcessor.applyInstallation(
            address(dao),
            PluginSetupProcessor.ApplyInstallationParams(
                PluginSetupRef(PluginRepo.Tag(1, 1), pluginRepo),
                plugin,
                preparedSetupData.permissions,
                hashHelpers(preparedSetupData.helpers)
            )
        );
    }

    function grantApplyInstallationPermissions(DAO dao) internal {
        // The PSP can manage permissions on the new DAO
        dao.grant(address(dao), address(settings.pluginSetupProcessor), dao.ROOT_PERMISSION_ID());

        // This factory can call applyInstallation() on the PSP
        dao.grant(
            address(settings.pluginSetupProcessor),
            address(this),
            settings.pluginSetupProcessor.APPLY_INSTALLATION_PERMISSION_ID()
        );
    }

    function revokeApplyInstallationPermissions(DAO dao) internal {
        // Revoking the permission for the factory to call applyInstallation() on the PSP
        dao.revoke(
            address(settings.pluginSetupProcessor),
            address(this),
            settings.pluginSetupProcessor.APPLY_INSTALLATION_PERMISSION_ID()
        );

        // Revoke the PSP permission to manage permissions on the new DAO
        dao.revoke(address(dao), address(settings.pluginSetupProcessor), dao.ROOT_PERMISSION_ID());
    }

    function revokeOwnerPermission(DAO dao) internal {
        dao.revoke(address(dao), address(this), dao.ROOT_PERMISSION_ID());
    }

    // Getters

    function getSettings() public view returns (DeploymentSettings memory) {
        return settings;
    }

    function getDeployment() public view returns (Deployment memory) {
        return deployment;
    }
}
