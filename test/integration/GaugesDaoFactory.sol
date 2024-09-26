// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {GaugesDaoFactory, Deployment, DeploymentParameters, TokenParameters} from "../../src/factory/GaugesDaoFactory.sol";
import {MockPluginSetupProcessor} from "../mocks/osx/MockPSP.sol";
import {MockPluginRepoRegistry} from "../mocks/osx/MockPluginRepoRegistry.sol";
import {MockDAOFactory} from "../mocks/osx/MockDaoFactory.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginRepoRegistry} from "@aragon/osx/framework/plugin/repo/PluginRepoRegistry.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {GovernanceERC20} from "@aragon/osx/token/ERC20/governance/GovernanceERC20.sol";
import {GovernanceWrappedERC20} from "@aragon/osx/token/ERC20/governance/GovernanceWrappedERC20.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {Addresslist} from "@aragon/osx/plugins/utils/Addresslist.sol";
import {MultisigSetup as MultisigPluginSetup} from "@aragon/osx/plugins/governance/multisig/MultisigSetup.sol";
import {SimpleGaugeVoterSetup, VotingEscrow, Clock, Lock, QuadraticIncreasingEscrow, ExitQueue, SimpleGaugeVoter} from "../../src/voting/SimpleGaugeVoterSetup.sol";

contract GaugesDaoFactoryTest is Test {
    function test_ShouldStoreTheSettings_1() public {
        address[] memory multisigMembers = new address[](13);
        for (uint256 i = 0; i < 13; i++) {
            multisigMembers[i] = address(uint160(i + 5));
        }

        SimpleGaugeVoterSetup gaugeVoterPluginSetup = new SimpleGaugeVoterSetup(
            address(new SimpleGaugeVoter()),
            address(new QuadraticIncreasingEscrow()),
            address(new ExitQueue()),
            address(new VotingEscrow()),
            address(new Clock()),
            address(new Lock())
        );

        MockPluginRepoRegistry pRepoRegistry = new MockPluginRepoRegistry();
        PluginRepoFactory pRefoFactory = new PluginRepoFactory(
            PluginRepoRegistry(address(pRepoRegistry))
        );
        MockPluginSetupProcessor psp = new MockPluginSetupProcessor(address(0));
        MockDAOFactory daoFactory = new MockDAOFactory(psp);

        TokenParameters[] memory tokenParameters = new TokenParameters[](2);
        tokenParameters[0] = TokenParameters({
            token: address(111),
            veTokenName: "Name 1",
            veTokenSymbol: "TK1"
        });
        tokenParameters[1] = TokenParameters({
            token: address(222),
            veTokenName: "Name 2",
            veTokenSymbol: "TK2"
        });

        DeploymentParameters memory creationParams = DeploymentParameters({
            // Multisig settings
            minApprovals: 2,
            multisigMembers: multisigMembers,
            // Gauge Voter
            tokenParameters: tokenParameters,
            feePercent: 0.5 ether,
            warmupPeriod: 1234,
            cooldownPeriod: 2345,
            minLockDuration: 3456,
            votingPaused: false,
            // Standard multisig repo
            multisigPluginRepo: PluginRepo(address(5555)),
            multisigPluginRelease: 1,
            multisigPluginBuild: 2,
            // Voter plugin setup and ENS
            voterPluginSetup: gaugeVoterPluginSetup,
            voterEnsSubdomain: "gauge-ens-subdomain",
            // OSx addresses
            osxDaoFactory: address(daoFactory),
            pluginSetupProcessor: PluginSetupProcessor(address(psp)),
            pluginRepoFactory: pRefoFactory
        });

        GaugesDaoFactory factory = new GaugesDaoFactory(creationParams);

        // Check
        DeploymentParameters memory actualParams = factory.getDeploymentParameters();
        assertEq(actualParams.minApprovals, creationParams.minApprovals, "Incorrect minApprovals");
        assertEq(
            actualParams.multisigMembers.length,
            creationParams.multisigMembers.length,
            "Incorrect multisigMembers.length"
        );
        for (uint256 i = 0; i < 13; i++) {
            assertEq(multisigMembers[i], address(uint160(i + 5)), "Incorrect member address");
        }

        assertEq(
            actualParams.tokenParameters.length,
            creationParams.tokenParameters.length,
            "Incorrect tokenParameters.length"
        );
        assertEq(
            actualParams.tokenParameters[0].token,
            creationParams.tokenParameters[0].token,
            "Incorrect tokenParameters[0].token"
        );
        assertEq(
            actualParams.tokenParameters[0].veTokenName,
            creationParams.tokenParameters[0].veTokenName,
            "Incorrect tokenParameters[0].veTokenName"
        );
        assertEq(
            actualParams.tokenParameters[0].veTokenSymbol,
            creationParams.tokenParameters[0].veTokenSymbol,
            "Incorrect tokenParameters[0].veTokenSymbol"
        );
        assertEq(
            actualParams.tokenParameters[1].token,
            creationParams.tokenParameters[1].token,
            "Incorrect tokenParameters[1].token"
        );
        assertEq(
            actualParams.tokenParameters[1].veTokenName,
            creationParams.tokenParameters[1].veTokenName,
            "Incorrect tokenParameters[1].veTokenName"
        );
        assertEq(
            actualParams.tokenParameters[1].veTokenSymbol,
            creationParams.tokenParameters[1].veTokenSymbol,
            "Incorrect tokenParameters[1].veTokenSymbol"
        );

        assertEq(actualParams.feePercent, creationParams.feePercent, "Incorrect feePercent");
        assertEq(actualParams.warmupPeriod, creationParams.warmupPeriod, "Incorrect warmupPeriod");
        assertEq(
            actualParams.cooldownPeriod,
            creationParams.cooldownPeriod,
            "Incorrect cooldownPeriod"
        );
        assertEq(
            actualParams.minLockDuration,
            creationParams.minLockDuration,
            "Incorrect minLockDuration"
        );
        assertEq(actualParams.votingPaused, creationParams.votingPaused, "Incorrect votingPaused");

        assertEq(
            address(actualParams.multisigPluginRepo),
            address(creationParams.multisigPluginRepo),
            "Incorrect multisigPluginRepo"
        );
        assertEq(
            actualParams.multisigPluginRelease,
            creationParams.multisigPluginRelease,
            "Incorrect multisigPluginRelease"
        );
        assertEq(
            actualParams.multisigPluginBuild,
            creationParams.multisigPluginBuild,
            "Incorrect multisigPluginBuild"
        );
        assertEq(
            address(actualParams.voterPluginSetup),
            address(creationParams.voterPluginSetup),
            "Incorrect voterPluginSetup"
        );
        assertEq(
            actualParams.voterEnsSubdomain,
            creationParams.voterEnsSubdomain,
            "Incorrect voterEnsSubdomain"
        );

        assertEq(
            address(actualParams.osxDaoFactory),
            address(creationParams.osxDaoFactory),
            "Incorrect osxDaoFactory"
        );
        assertEq(
            address(actualParams.pluginSetupProcessor),
            address(creationParams.pluginSetupProcessor),
            "Incorrect pluginSetupProcessor"
        );
        assertEq(
            address(actualParams.pluginRepoFactory),
            address(creationParams.pluginRepoFactory),
            "Incorrect pluginRepoFactory"
        );
    }

    function test_ShouldStoreTheSettings_2() public {
        address[] memory multisigMembers = new address[](13);
        for (uint256 i = 0; i < 13; i++) {
            multisigMembers[i] = address(uint160(i + 10));
        }

        SimpleGaugeVoterSetup gaugeVoterPluginSetup = new SimpleGaugeVoterSetup(
            address(new SimpleGaugeVoter()),
            address(new QuadraticIncreasingEscrow()),
            address(new ExitQueue()),
            address(new VotingEscrow()),
            address(new Clock()),
            address(new Lock())
        );

        MockPluginRepoRegistry pRepoRegistry = new MockPluginRepoRegistry();
        PluginRepoFactory pRefoFactory = new PluginRepoFactory(
            PluginRepoRegistry(address(pRepoRegistry))
        );
        MockPluginSetupProcessor psp = new MockPluginSetupProcessor(address(0));
        MockDAOFactory daoFactory = new MockDAOFactory(psp);

        TokenParameters[] memory tokenParameters = new TokenParameters[](2);
        tokenParameters[0] = TokenParameters({
            token: address(333),
            veTokenName: "Name 3",
            veTokenSymbol: "TK3"
        });
        tokenParameters[1] = TokenParameters({
            token: address(444),
            veTokenName: "Name 4",
            veTokenSymbol: "TK4"
        });

        DeploymentParameters memory creationParams = DeploymentParameters({
            // Multisig settings
            minApprovals: 3,
            multisigMembers: multisigMembers,
            // Gauge Voter
            tokenParameters: tokenParameters,
            feePercent: 0.1 ether,
            warmupPeriod: 7654,
            cooldownPeriod: 6543,
            minLockDuration: 5432,
            votingPaused: true,
            // Standard multisig repo
            multisigPluginRepo: PluginRepo(address(3333)),
            multisigPluginRelease: 2,
            multisigPluginBuild: 10,
            // Voter plugin setup and ENS
            voterPluginSetup: gaugeVoterPluginSetup,
            voterEnsSubdomain: "gauge-ens-subdomain-bis",
            // OSx addresses
            osxDaoFactory: address(daoFactory),
            pluginSetupProcessor: PluginSetupProcessor(address(psp)),
            pluginRepoFactory: pRefoFactory
        });

        GaugesDaoFactory factory = new GaugesDaoFactory(creationParams);

        // Check
        DeploymentParameters memory actualParams = factory.getDeploymentParameters();
        assertEq(actualParams.minApprovals, creationParams.minApprovals, "Incorrect minApprovals");
        assertEq(
            actualParams.multisigMembers.length,
            creationParams.multisigMembers.length,
            "Incorrect multisigMembers.length"
        );
        for (uint256 i = 0; i < 13; i++) {
            assertEq(multisigMembers[i], address(uint160(i + 10)), "Incorrect member address");
        }

        assertEq(
            actualParams.tokenParameters.length,
            creationParams.tokenParameters.length,
            "Incorrect tokenParameters.length"
        );
        assertEq(
            actualParams.tokenParameters[0].token,
            creationParams.tokenParameters[0].token,
            "Incorrect tokenParameters[0].token"
        );
        assertEq(
            actualParams.tokenParameters[0].veTokenName,
            creationParams.tokenParameters[0].veTokenName,
            "Incorrect tokenParameters[0].veTokenName"
        );
        assertEq(
            actualParams.tokenParameters[0].veTokenSymbol,
            creationParams.tokenParameters[0].veTokenSymbol,
            "Incorrect tokenParameters[0].veTokenSymbol"
        );
        assertEq(
            actualParams.tokenParameters[1].token,
            creationParams.tokenParameters[1].token,
            "Incorrect tokenParameters[1].token"
        );
        assertEq(
            actualParams.tokenParameters[1].veTokenName,
            creationParams.tokenParameters[1].veTokenName,
            "Incorrect tokenParameters[1].veTokenName"
        );
        assertEq(
            actualParams.tokenParameters[1].veTokenSymbol,
            creationParams.tokenParameters[1].veTokenSymbol,
            "Incorrect tokenParameters[1].veTokenSymbol"
        );

        assertEq(actualParams.feePercent, creationParams.feePercent, "Incorrect feePercent");
        assertEq(actualParams.warmupPeriod, creationParams.warmupPeriod, "Incorrect warmupPeriod");
        assertEq(
            actualParams.cooldownPeriod,
            creationParams.cooldownPeriod,
            "Incorrect cooldownPeriod"
        );
        assertEq(
            actualParams.minLockDuration,
            creationParams.minLockDuration,
            "Incorrect minLockDuration"
        );
        assertEq(actualParams.votingPaused, creationParams.votingPaused, "Incorrect votingPaused");

        assertEq(
            address(actualParams.multisigPluginRepo),
            address(creationParams.multisigPluginRepo),
            "Incorrect multisigPluginRepo"
        );
        assertEq(
            actualParams.multisigPluginRelease,
            creationParams.multisigPluginRelease,
            "Incorrect multisigPluginRelease"
        );
        assertEq(
            actualParams.multisigPluginBuild,
            creationParams.multisigPluginBuild,
            "Incorrect multisigPluginBuild"
        );
        assertEq(
            address(actualParams.voterPluginSetup),
            address(creationParams.voterPluginSetup),
            "Incorrect voterPluginSetup"
        );
        assertEq(
            actualParams.voterEnsSubdomain,
            creationParams.voterEnsSubdomain,
            "Incorrect voterEnsSubdomain"
        );

        assertEq(
            address(actualParams.osxDaoFactory),
            address(creationParams.osxDaoFactory),
            "Incorrect osxDaoFactory"
        );
        assertEq(
            address(actualParams.pluginSetupProcessor),
            address(creationParams.pluginSetupProcessor),
            "Incorrect pluginSetupProcessor"
        );
        assertEq(
            address(actualParams.pluginRepoFactory),
            address(creationParams.pluginRepoFactory),
            "Incorrect pluginRepoFactory"
        );
    }

    function test_StandardDeployment_1() public {
        address[] memory multisigMembers = new address[](13);
        for (uint256 i = 0; i < 13; i++) {
            multisigMembers[i] = address(uint160(i + 5));
        }

        PluginRepo multisigPluginRepo = PluginRepo(vm.envAddress("MULTISIG_PLUGIN_REPO_ADDRESS"));
        SimpleGaugeVoterSetup gaugeVoterPluginSetup = new SimpleGaugeVoterSetup(
            address(new SimpleGaugeVoter()),
            address(new QuadraticIncreasingEscrow()),
            address(new ExitQueue()),
            address(new VotingEscrow()),
            address(new Clock()),
            address(new Lock())
        );

        MockPluginRepoRegistry pRepoRegistry = new MockPluginRepoRegistry();
        PluginRepoFactory pRefoFactory = new PluginRepoFactory(
            PluginRepoRegistry(address(pRepoRegistry))
        );
        MockPluginSetupProcessor psp = new MockPluginSetupProcessor(address(0));
        MockDAOFactory daoFactory = new MockDAOFactory(psp);

        TokenParameters[] memory tokenParameters = new TokenParameters[](2);
        tokenParameters[0] = TokenParameters({
            token: address(111),
            veTokenName: "Name 1",
            veTokenSymbol: "TK1"
        });
        tokenParameters[1] = TokenParameters({
            token: address(222),
            veTokenName: "Name 2",
            veTokenSymbol: "TK2"
        });

        DeploymentParameters memory creationParams = DeploymentParameters({
            // Multisig settings
            minApprovals: 2,
            multisigMembers: multisigMembers,
            // Gauge Voter
            tokenParameters: tokenParameters,
            feePercent: 0.5 ether,
            warmupPeriod: 1234,
            cooldownPeriod: 2345,
            minLockDuration: 3456,
            votingPaused: false,
            // Standard multisig repo
            multisigPluginRepo: multisigPluginRepo,
            multisigPluginRelease: 1,
            multisigPluginBuild: 2,
            // Voter plugin setup and ENS
            voterPluginSetup: gaugeVoterPluginSetup,
            voterEnsSubdomain: "gauge-ens-subdomain",
            // OSx addresses
            osxDaoFactory: address(daoFactory),
            pluginSetupProcessor: PluginSetupProcessor(address(psp)),
            pluginRepoFactory: pRefoFactory
        });

        GaugesDaoFactory factory = new GaugesDaoFactory(creationParams);

        factory.deployOnce();
        Deployment memory deployment = factory.getDeployment();

        vm.roll(block.number + 1); // mint one block

        // DAO checks

        assertNotEq(address(deployment.dao), address(0), "Empty DAO field");
        assertEq(deployment.dao.daoURI(), "", "DAO URI should be empty");
        assertEq(
            address(deployment.dao.signatureValidator()),
            address(0),
            "signatureValidator should be empty"
        );
        assertEq(
            address(deployment.dao.getTrustedForwarder()),
            address(0),
            "trustedForwarder should be empty"
        );
        assertEq(
            deployment.dao.hasPermission(
                address(deployment.dao),
                address(deployment.dao),
                deployment.dao.ROOT_PERMISSION_ID(),
                bytes("")
            ),
            true,
            "The DAO should be ROOT on itself"
        );
        assertEq(
            deployment.dao.hasPermission(
                address(deployment.dao),
                address(deployment.dao),
                deployment.dao.UPGRADE_DAO_PERMISSION_ID(),
                bytes("")
            ),
            true,
            "The DAO should have UPGRADE_DAO_PERMISSION on itself"
        );
        assertEq(
            deployment.dao.hasPermission(
                address(deployment.dao),
                address(deployment.dao),
                deployment.dao.REGISTER_STANDARD_CALLBACK_PERMISSION_ID(),
                bytes("")
            ),
            true,
            "The DAO should have REGISTER_STANDARD_CALLBACK_PERMISSION_ID on itself"
        );

        // Multisig plugin

        assertNotEq(address(deployment.multisigPlugin), address(0), "Empty multisig field");
        assertEq(
            deployment.multisigPlugin.lastMultisigSettingsChange(),
            block.number - 1,
            "Invalid lastMultisigSettingsChange"
        );
        assertEq(deployment.multisigPlugin.proposalCount(), 0, "Invalid proposal count");
        assertEq(deployment.multisigPlugin.addresslistLength(), 13, "Invalid addresslistLength");
        for (uint256 i = 0; i < 13; i++) {
            assertEq(
                deployment.multisigPlugin.isMember(multisigMembers[i]),
                true,
                "Should be a member"
            );
        }
        for (uint256 i = 14; i < 50; i++) {
            assertEq(
                deployment.multisigPlugin.isMember(address(uint160(i))),
                false,
                "Should not be a member"
            );
        }
        {
            (bool onlyListed, uint16 minApprovals) = deployment.multisigPlugin.multisigSettings();

            assertEq(onlyListed, true, "Invalid onlyListed");
            assertEq(minApprovals, 7, "Invalid minApprovals");
        }

        // Gauge voter plugin

        // assertNotEq(
        //     address(deployment.optimisticTokenVotingPlugin),
        //     address(0),
        //     "Empty optimisticTokenVotingPlugin field"
        // );
        // assertEq(
        //     address(deployment.optimisticTokenVotingPlugin.votingToken()),
        //     address(tokenAddress),
        //     "Invalid votingToken"
        // );
        // assertEq(
        //     address(deployment.optimisticTokenVotingPlugin.gaugesL1()),
        //     address(gaugesL1ContractAddress),
        //     "Invalid gaugesL1"
        // );
        // assertEq(
        //     address(deployment.optimisticTokenVotingPlugin.gaugesBridge()),
        //     address(gaugesBridgeAddress),
        //     "Invalid gaugesBridge"
        // );
        // assertEq(
        //     deployment.optimisticTokenVotingPlugin.proposalCount(),
        //     0,
        //     "Invalid proposal count"
        // );
        // {
        //     (
        //         uint32 minVetoRatio,
        //         uint64 minDuration,
        //         uint64 l2InactivityPeriod,
        //         uint64 l2AggregationGracePeriod,
        //         bool skipL2
        //     ) = deployment.optimisticTokenVotingPlugin.governanceSettings();

        //     assertEq(minVetoRatio, 200_000, "Invalid minVetoRatio");
        //     assertEq(minDuration, 0, "Invalid minDuration"); // 10 days is enforced on the condition contract
        //     assertEq(l2InactivityPeriod, 10 minutes, "Invalid l2InactivityPeriod");
        //     assertEq(l2AggregationGracePeriod, 2 days, "Invalid l2AggregationGracePeriod");
        //     assertEq(skipL2, false, "Invalid skipL2");
        // }

        // PLUGIN REPO's

        PluginRepo.Version memory version;

        // Multisig code
        version = multisigPluginRepo.getLatestVersion(1);
        assertEq(
            address(MultisigPluginSetup(version.pluginSetup).implementation()),
            address(deployment.multisigPlugin.implementation()),
            "Invalid multisigPluginSetup"
        );

        // // Gauge voter plugin
        // assertNotEq(
        //     address(deployment.optimisticTokenVotingPluginRepo),
        //     address(0),
        //     "Empty optimisticTokenVotingPluginRepo field"
        // );
        // assertEq(
        //     deployment.optimisticTokenVotingPluginRepo.latestRelease(),
        //     1,
        //     "Invalid latestRelease"
        // );
        // assertEq(deployment.optimisticTokenVotingPluginRepo.buildCount(1), 1, "Invalid buildCount");
        // version = deployment.optimisticTokenVotingPluginRepo.getLatestVersion(1);
        // assertEq(
        //     address(version.pluginSetup),
        //     address(gaugeVoterPluginSetup),
        //     "Invalid pluginSetup"
        // );
    }

    // function test_StandardDeployment_2() public {
    //     DAO tempMgmtDao = DAO(
    //         payable(
    //             createProxyAndCall(
    //                 address(DAO_BASE),
    //                 abi.encodeCall(DAO.initialize, ("", address(this), address(0x0), ""))
    //             )
    //         )
    //     );

    //     GovernanceERC20Mock tokenAddress = new GovernanceERC20Mock(address(tempMgmtDao));
    //     GaugesL1Mock gaugesL1ContractAddress = new GaugesL1Mock();
    //     address gaugesBridgeAddress = address(0x5678);
    //     address[] memory multisigMembers = new address[](16);
    //     for (uint256 i = 0; i < 16; i++) {
    //         multisigMembers[i] = address(uint160(i + 1));
    //     }

    //     MultisigPluginSetup multisigPluginSetup = new MultisigPluginSetup();
    //     EmergencyMultisigPluginSetup emergencyMultisigPluginSetup = new EmergencyMultisigPluginSetup();
    //     GovernanceERC20.MintSettings memory mintSettings = GovernanceERC20.MintSettings({
    //         receivers: new address[](0),
    //         amounts: new uint256[](0)
    //     });
    //     OptimisticTokenVotingPluginSetup voterPluginSetup = new OptimisticTokenVotingPluginSetup(
    //         new GovernanceERC20(tempMgmtDao, "", "", mintSettings),
    //         new GovernanceWrappedERC20(tokenAddress, "", "")
    //     );

    //     PluginRepoFactory pRefoFactory;
    //     MockPluginSetupProcessor psp;
    //     {
    //         MockPluginRepoRegistry pRepoRegistry = new MockPluginRepoRegistry();
    //         pRefoFactory = new PluginRepoFactory(PluginRepoRegistry(address(pRepoRegistry)));

    //         address[] memory setups = new address[](3);
    //         // adding in reverse order (stack)
    //         setups[2] = address(multisigPluginSetup);
    //         setups[1] = address(emergencyMultisigPluginSetup);
    //         setups[0] = address(voterPluginSetup);
    //         psp = new MockPluginSetupProcessor(setups);
    //     }
    //     MockDAOFactory daoFactory = new MockDAOFactory(psp);

    //     DeploymentParameters memory creationParams = DeploymentParameters({
    //         // Gauges contract settings
    //         tokenAddress: tokenAddress,
    //         gaugesL1ContractAddress: address(gaugesL1ContractAddress), // address
    //         gaugesBridgeAddress: gaugesBridgeAddress, // address
    //         l2InactivityPeriod: 27 minutes, // uint64
    //         l2AggregationGracePeriod: 3 days, // uint64
    //         skipL2: true,
    //         // Voting settings
    //         minVetoRatio: 456_000, // uint32
    //         minStdProposalDuration: 21 days, // uint64
    //         minStdApprovals: 9, // uint16
    //         minEmergencyApprovals: 15, // uint16
    //         // OSx contracts
    //         osxDaoFactory: address(daoFactory),
    //         pluginSetupProcessor: PluginSetupProcessor(address(psp)), // PluginSetupProcessor
    //         pluginRepoFactory: PluginRepoFactory(address(pRefoFactory)), // PluginRepoFactory
    //         // Plugin setup's
    //         multisigPluginSetup: multisigPluginSetup,
    //         emergencyMultisigPluginSetup: emergencyMultisigPluginSetup,
    //         voterPluginSetup: voterPluginSetup,
    //         // Multisig
    //         multisigMembers: multisigMembers, // address[]
    //         multisigExpirationPeriod: 22 days,
    //         // ENS
    //         stdMultisigEnsDomain: "multisig", // string
    //         emergencyMultisigEnsDomain: "eMultisig", // string
    //         optimisticTokenVotingEnsDomain: "optimistic" // string
    //     });

    //     // Deploy
    //     GaugesDaoFactory factory = new GaugesDaoFactory(creationParams);

    //     factory.deployOnce();
    //     GaugesDaoFactory.Deployment memory deployment = factory.getDeployment();

    //     vm.roll(block.number + 1); // mint one block

    //     // DAO checks

    //     assertNotEq(address(deployment.dao), address(0), "Empty DAO field");
    //     assertEq(deployment.dao.daoURI(), "", "DAO URI should be empty");
    //     assertEq(
    //         address(deployment.dao.signatureValidator()),
    //         address(0),
    //         "signatureValidator should be empty"
    //     );
    //     assertEq(
    //         address(deployment.dao.getTrustedForwarder()),
    //         address(0),
    //         "trustedForwarder should be empty"
    //     );
    //     assertEq(
    //         deployment.dao.hasPermission(
    //             address(deployment.dao),
    //             address(deployment.dao),
    //             deployment.dao.ROOT_PERMISSION_ID(),
    //             bytes("")
    //         ),
    //         true,
    //         "The DAO should be ROOT on itself"
    //     );
    //     assertEq(
    //         deployment.dao.hasPermission(
    //             address(deployment.dao),
    //             address(deployment.dao),
    //             deployment.dao.UPGRADE_DAO_PERMISSION_ID(),
    //             bytes("")
    //         ),
    //         true,
    //         "The DAO should have UPGRADE_DAO_PERMISSION on itself"
    //     );
    //     assertEq(
    //         deployment.dao.hasPermission(
    //             address(deployment.dao),
    //             address(deployment.dao),
    //             deployment.dao.REGISTER_STANDARD_CALLBACK_PERMISSION_ID(),
    //             bytes("")
    //         ),
    //         true,
    //         "The DAO should have REGISTER_STANDARD_CALLBACK_PERMISSION_ID on itself"
    //     );

    //     // Multisig plugin

    //     assertNotEq(address(deployment.multisigPlugin), address(0), "Empty multisig field");
    //     assertEq(
    //         deployment.multisigPlugin.lastMultisigSettingsChange(),
    //         block.number - 1,
    //         "Invalid lastMultisigSettingsChange"
    //     );
    //     assertEq(deployment.multisigPlugin.proposalCount(), 0, "Invalid proposal count");
    //     assertEq(deployment.multisigPlugin.addresslistLength(), 16, "Invalid addresslistLength");
    //     for (uint256 i = 0; i < 16; i++) {
    //         assertEq(
    //             deployment.multisigPlugin.isMember(multisigMembers[i]),
    //             true,
    //             "Should be a member"
    //         );
    //     }
    //     for (uint256 i = 17; i < 50; i++) {
    //         assertEq(
    //             deployment.multisigPlugin.isMember(address(uint160(i))),
    //             false,
    //             "Should not be a member"
    //         );
    //     }
    //     {
    //         (
    //             bool onlyListed,
    //             uint16 minApprovals,
    //             uint64 destinationProposalDuration,
    //             uint64 expirationPeriod
    //         ) = deployment.multisigPlugin.multisigSettings();

    //         assertEq(onlyListed, true, "Invalid onlyListed");
    //         assertEq(minApprovals, 9, "Invalid minApprovals");
    //         assertEq(destinationProposalDuration, 21 days, "Invalid destinationProposalDuration");
    //         assertEq(expirationPeriod, 22 days, "Invalid expirationPeriod");
    //     }

    //     // Emergency Multisig plugin

    //     assertNotEq(
    //         address(deployment.emergencyMultisigPlugin),
    //         address(0),
    //         "Empty emergencyMultisig field"
    //     );
    //     assertEq(
    //         deployment.emergencyMultisigPlugin.lastMultisigSettingsChange(),
    //         block.number - 1,
    //         "Invalid lastMultisigSettingsChange"
    //     );
    //     assertEq(deployment.emergencyMultisigPlugin.proposalCount(), 0, "Invalid proposal count");
    //     for (uint256 i = 0; i < 16; i++) {
    //         assertEq(
    //             deployment.emergencyMultisigPlugin.isMember(multisigMembers[i]),
    //             true,
    //             "Should be a member"
    //         );
    //     }
    //     for (uint256 i = 17; i < 50; i++) {
    //         assertEq(
    //             deployment.emergencyMultisigPlugin.isMember(address(uint160(i))),
    //             false,
    //             "Should not be a member"
    //         );
    //     }
    //     {
    //         (
    //             bool onlyListed,
    //             uint16 minApprovals,
    //             Addresslist addresslistSource,
    //             uint64 expirationPeriod
    //         ) = deployment.emergencyMultisigPlugin.multisigSettings();

    //         assertEq(onlyListed, true, "Invalid onlyListed");
    //         assertEq(minApprovals, 15, "Invalid minApprovals");
    //         assertEq(
    //             address(addresslistSource),
    //             address(deployment.multisigPlugin),
    //             "Invalid addresslistSource"
    //         );
    //         assertEq(expirationPeriod, 22 days, "Invalid expirationPeriod");
    //     }

    //     // Optimistic token voting plugin checks

    //     assertNotEq(
    //         address(deployment.optimisticTokenVotingPlugin),
    //         address(0),
    //         "Empty optimisticTokenVotingPlugin field"
    //     );
    //     assertEq(
    //         address(deployment.optimisticTokenVotingPlugin.votingToken()),
    //         address(tokenAddress),
    //         "Invalid votingToken"
    //     );
    //     assertEq(
    //         address(deployment.optimisticTokenVotingPlugin.gaugesL1()),
    //         address(gaugesL1ContractAddress),
    //         "Invalid gaugesL1"
    //     );
    //     assertEq(
    //         address(deployment.optimisticTokenVotingPlugin.gaugesBridge()),
    //         address(gaugesBridgeAddress),
    //         "Invalid gaugesBridge"
    //     );
    //     assertEq(
    //         deployment.optimisticTokenVotingPlugin.proposalCount(),
    //         0,
    //         "Invalid proposal count"
    //     );
    //     {
    //         (
    //             uint32 minVetoRatio,
    //             uint64 minDuration,
    //             uint64 l2InactivityPeriod,
    //             uint64 l2AggregationGracePeriod,
    //             bool skipL2
    //         ) = deployment.optimisticTokenVotingPlugin.governanceSettings();

    //         assertEq(minVetoRatio, 456_000, "Invalid minVetoRatio");
    //         assertEq(minDuration, 0, "Invalid minDuration"); // 10 days is enforced on the condition contract
    //         assertEq(l2InactivityPeriod, 27 minutes, "Invalid l2InactivityPeriod");
    //         assertEq(l2AggregationGracePeriod, 3 days, "Invalid l2AggregationGracePeriod");
    //         assertEq(skipL2, true, "Invalid skipL2");
    //     }

    //     // PLUGIN REPO's

    //     PluginRepo.Version memory version;

    //     // Multisig repo
    //     assertNotEq(
    //         address(deployment.multisigPluginRepo),
    //         address(0),
    //         "Empty multisigPluginRepo field"
    //     );
    //     assertEq(deployment.multisigPluginRepo.latestRelease(), 1, "Invalid latestRelease");
    //     assertEq(deployment.multisigPluginRepo.buildCount(1), 1, "Invalid buildCount");
    //     version = deployment.multisigPluginRepo.getLatestVersion(1);
    //     assertEq(
    //         address(version.pluginSetup),
    //         address(multisigPluginSetup),
    //         "Invalid multisigPluginSetup"
    //     );

    //     // Emergency multisig repo
    //     assertNotEq(
    //         address(deployment.emergencyMultisigPluginRepo),
    //         address(0),
    //         "Empty emergencyMultisigPluginRepo field"
    //     );
    //     assertEq(
    //         deployment.emergencyMultisigPluginRepo.latestRelease(),
    //         1,
    //         "Invalid latestRelease"
    //     );
    //     assertEq(deployment.emergencyMultisigPluginRepo.buildCount(1), 1, "Invalid buildCount");
    //     version = deployment.emergencyMultisigPluginRepo.getLatestVersion(1);
    //     assertEq(
    //         address(version.pluginSetup),
    //         address(emergencyMultisigPluginSetup),
    //         "Invalid emergencyMultisigPluginSetup"
    //     );

    //     // Optimistic repo
    //     assertNotEq(
    //         address(deployment.optimisticTokenVotingPluginRepo),
    //         address(0),
    //         "Empty optimisticTokenVotingPluginRepo field"
    //     );
    //     assertEq(
    //         deployment.optimisticTokenVotingPluginRepo.latestRelease(),
    //         1,
    //         "Invalid latestRelease"
    //     );
    //     assertEq(deployment.optimisticTokenVotingPluginRepo.buildCount(1), 1, "Invalid buildCount");
    //     version = deployment.optimisticTokenVotingPluginRepo.getLatestVersion(1);
    //     assertEq(
    //         address(version.pluginSetup),
    //         address(voterPluginSetup),
    //         "Invalid voterPluginSetup"
    //     );

    //     // PUBLIC KEY REGISTRY
    //     assertNotEq(
    //         address(deployment.publicKeyRegistry),
    //         address(0),
    //         "Empty publicKeyRegistry field"
    //     );
    //     assertEq(
    //         deployment.publicKeyRegistry.registeredWalletCount(),
    //         0,
    //         "Invalid registeredWalletCount"
    //     );
    // }

    // function test_MultipleDeploysDoNothing() public {
    //     DAO tempMgmtDao = DAO(
    //         payable(
    //             createProxyAndCall(
    //                 address(DAO_BASE),
    //                 abi.encodeCall(DAO.initialize, ("", address(this), address(0x0), ""))
    //             )
    //         )
    //     );

    //     GovernanceERC20Mock tokenAddress = new GovernanceERC20Mock(address(tempMgmtDao));
    //     GaugesL1Mock gaugesL1ContractAddress = new GaugesL1Mock();
    //     address gaugesBridgeAddress = address(0x1234);
    //     address[] memory multisigMembers = new address[](13);
    //     for (uint256 i = 0; i < 13; i++) {
    //         multisigMembers[i] = address(uint160(i + 1));
    //     }

    //     MultisigPluginSetup multisigPluginSetup = new MultisigPluginSetup();
    //     EmergencyMultisigPluginSetup emergencyMultisigPluginSetup = new EmergencyMultisigPluginSetup();
    //     GovernanceERC20.MintSettings memory mintSettings = GovernanceERC20.MintSettings({
    //         receivers: new address[](0),
    //         amounts: new uint256[](0)
    //     });
    //     OptimisticTokenVotingPluginSetup voterPluginSetup = new OptimisticTokenVotingPluginSetup(
    //         new GovernanceERC20(tempMgmtDao, "", "", mintSettings),
    //         new GovernanceWrappedERC20(tokenAddress, "", "")
    //     );

    //     PluginRepoFactory pRefoFactory;
    //     MockPluginSetupProcessor psp;
    //     {
    //         MockPluginRepoRegistry pRepoRegistry = new MockPluginRepoRegistry();
    //         pRefoFactory = new PluginRepoFactory(PluginRepoRegistry(address(pRepoRegistry)));

    //         address[] memory setups = new address[](3);
    //         // adding in reverse order (stack)
    //         setups[2] = address(multisigPluginSetup);
    //         setups[1] = address(emergencyMultisigPluginSetup);
    //         setups[0] = address(voterPluginSetup);
    //         psp = new MockPluginSetupProcessor(setups);
    //     }
    //     MockDAOFactory daoFactory = new MockDAOFactory(psp);

    //     DeploymentParameters memory creationParams = DeploymentParameters({
    //         // Gauges contract settings
    //         tokenAddress: tokenAddress,
    //         gaugesL1ContractAddress: address(gaugesL1ContractAddress), // address
    //         gaugesBridgeAddress: gaugesBridgeAddress, // address
    //         l2InactivityPeriod: 10 minutes, // uint64
    //         l2AggregationGracePeriod: 2 days, // uint64
    //         skipL2: false,
    //         // Voting settings
    //         minVetoRatio: 200_000, // uint32
    //         minStdProposalDuration: 10 days, // uint64
    //         minStdApprovals: 7, // uint16
    //         minEmergencyApprovals: 11, // uint16
    //         // OSx contracts
    //         osxDaoFactory: address(daoFactory),
    //         pluginSetupProcessor: PluginSetupProcessor(address(psp)), // PluginSetupProcessor
    //         pluginRepoFactory: PluginRepoFactory(address(pRefoFactory)), // PluginRepoFactory
    //         // Plugin setup's
    //         multisigPluginSetup: multisigPluginSetup,
    //         emergencyMultisigPluginSetup: emergencyMultisigPluginSetup,
    //         voterPluginSetup: voterPluginSetup,
    //         // Multisig
    //         multisigMembers: multisigMembers, // address[]
    //         multisigExpirationPeriod: 10 days,
    //         // ENS
    //         stdMultisigEnsDomain: "multisig", // string
    //         emergencyMultisigEnsDomain: "eMultisig", // string
    //         optimisticTokenVotingEnsDomain: "optimistic" // string
    //     });

    //     GaugesDaoFactory factory = new GaugesDaoFactory(creationParams);
    //     // ok
    //     factory.deployOnce();

    //     vm.expectRevert(abi.encodeWithSelector(GaugesDaoFactory.AlreadyDeployed.selector));
    //     factory.deployOnce();

    //     vm.expectRevert(abi.encodeWithSelector(GaugesDaoFactory.AlreadyDeployed.selector));
    //     factory.deployOnce();
    // }
}
