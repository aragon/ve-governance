// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {GaugesDaoFactory, Deployment, DeploymentParameters, TokenParameters} from "../../src/factory/GaugesDaoFactory.sol";
import {MockPluginSetupProcessor} from "../mocks/osx/MockPSP.sol";
import {MockPluginSetupProcessorMulti} from "../mocks/osx/MockPSPMulti.sol";
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
        MockPluginSetupProcessorMulti psp = new MockPluginSetupProcessorMulti(new address[](0));
        MockDAOFactory daoFactory = new MockDAOFactory(MockPluginSetupProcessor(address(psp)));

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
        MockPluginSetupProcessorMulti psp = new MockPluginSetupProcessorMulti(new address[](0));
        MockDAOFactory daoFactory = new MockDAOFactory(MockPluginSetupProcessor(address(psp)));

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

        PluginRepoFactory pRefoFactory = new PluginRepoFactory(
            PluginRepoRegistry(address(new MockPluginRepoRegistry()))
        );

        // Publish repo
        MultisigPluginSetup multisigPluginSetup = new MultisigPluginSetup();
        PluginRepo multisigPluginRepo = PluginRepoFactory(pRefoFactory)
            .createPluginRepoWithFirstVersion(
                "multisig-subdomain",
                address(multisigPluginSetup),
                address(this),
                " ",
                " "
            );

        SimpleGaugeVoterSetup gaugeVoterPluginSetup = new SimpleGaugeVoterSetup(
            address(new SimpleGaugeVoter()),
            address(new QuadraticIncreasingEscrow()),
            address(new ExitQueue()),
            address(new VotingEscrow()),
            address(new Clock()),
            address(new Lock())
        );

        TokenParameters[] memory tokenParameters = new TokenParameters[](2);
        tokenParameters[0] = TokenParameters({
            token: address(deployMockERC20("T1", "T1", 18)),
            veTokenName: "Name 1",
            veTokenSymbol: "TK1"
        });
        tokenParameters[1] = TokenParameters({
            token: address(deployMockERC20("T2", "T2", 18)),
            veTokenName: "Name 2",
            veTokenSymbol: "TK2"
        });

        // PSP with voter plugin setup and multisig
        MockPluginSetupProcessorMulti psp;
        {
            address[] memory pluginSetups = new address[](3);
            pluginSetups[0] = address(gaugeVoterPluginSetup); // Token 1
            pluginSetups[1] = address(gaugeVoterPluginSetup); // Token 2
            pluginSetups[2] = address(multisigPluginSetup);

            psp = new MockPluginSetupProcessorMulti(pluginSetups);
        }
        MockDAOFactory daoFactory = new MockDAOFactory(MockPluginSetupProcessor(address(psp)));

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
                deployment.multisigPlugin.isMember(address(uint160(i + 5))),
                false,
                "Should not be a member"
            );
        }
        {
            (bool onlyListed, uint16 minApprovals) = deployment.multisigPlugin.multisigSettings();

            assertEq(onlyListed, true, "Invalid onlyListed");
            assertEq(minApprovals, 2, "Invalid minApprovals");
        }

        // Gauge voter plugin

        assertEq(
            deployment.gaugeVoterPluginSets.length,
            2,
            "Incorrect gaugeVoterPluginSets length"
        );
        // 0
        assertNotEq(
            address(deployment.gaugeVoterPluginSets[0].plugin),
            address(0),
            "Empty plugin address"
        );
        assertEq(deployment.gaugeVoterPluginSets[0].plugin.paused(), false, "Should not be paused");
        assertNotEq(
            address(deployment.gaugeVoterPluginSets[0].curve),
            address(0),
            "Empty curve address"
        );
        assertEq(
            deployment.gaugeVoterPluginSets[0].curve.warmupPeriod(),
            1234,
            "Incorrect warmupPeriod"
        );
        assertNotEq(
            address(deployment.gaugeVoterPluginSets[0].exitQueue),
            address(0),
            "Empty exitQueue address"
        );
        assertEq(
            deployment.gaugeVoterPluginSets[0].exitQueue.feePercent(),
            0.5 ether,
            "Incorrect feePercent"
        );
        assertEq(
            deployment.gaugeVoterPluginSets[0].exitQueue.cooldown(),
            2345,
            "Incorrect cooldown"
        );
        assertEq(deployment.gaugeVoterPluginSets[0].exitQueue.minLock(), 3456, "Incorrect minLock");
        assertNotEq(
            address(deployment.gaugeVoterPluginSets[0].votingEscrow),
            address(0),
            "Empty votingEscrow address"
        );
        assertNotEq(
            address(deployment.gaugeVoterPluginSets[0].clock),
            address(0),
            "Empty clock address"
        );
        assertNotEq(
            address(deployment.gaugeVoterPluginSets[0].nftLock),
            address(0),
            "Empty nftLock address"
        );
        assertEq(
            deployment.gaugeVoterPluginSets[0].nftLock.name(),
            tokenParameters[0].veTokenName,
            "Incorrect veTokenName"
        );
        assertEq(
            deployment.gaugeVoterPluginSets[0].nftLock.symbol(),
            tokenParameters[0].veTokenSymbol,
            "Incorrect veTokenSymbol"
        );
        // 1
        assertNotEq(
            address(deployment.gaugeVoterPluginSets[1].plugin),
            address(0),
            "Empty plugin address"
        );
        assertEq(deployment.gaugeVoterPluginSets[1].plugin.paused(), false, "Should not be paused");
        assertNotEq(
            address(deployment.gaugeVoterPluginSets[1].curve),
            address(0),
            "Empty curve address"
        );
        assertEq(
            deployment.gaugeVoterPluginSets[1].curve.warmupPeriod(),
            1234,
            "Incorrect warmupPeriod"
        );
        assertNotEq(
            address(deployment.gaugeVoterPluginSets[1].exitQueue),
            address(0),
            "Empty exitQueue address"
        );
        assertEq(
            deployment.gaugeVoterPluginSets[1].exitQueue.feePercent(),
            0.5 ether,
            "Incorrect feePercent"
        );
        assertEq(
            deployment.gaugeVoterPluginSets[1].exitQueue.cooldown(),
            2345,
            "Incorrect cooldown"
        );
        assertEq(deployment.gaugeVoterPluginSets[1].exitQueue.minLock(), 3456, "Incorrect minLock");
        assertNotEq(
            address(deployment.gaugeVoterPluginSets[1].votingEscrow),
            address(0),
            "Empty votingEscrow address"
        );
        assertNotEq(
            address(deployment.gaugeVoterPluginSets[1].clock),
            address(0),
            "Empty clock address"
        );
        assertNotEq(
            address(deployment.gaugeVoterPluginSets[1].nftLock),
            address(0),
            "Empty nftLock address"
        );
        assertEq(
            deployment.gaugeVoterPluginSets[1].nftLock.name(),
            tokenParameters[1].veTokenName,
            "Incorrect veTokenName"
        );
        assertEq(
            deployment.gaugeVoterPluginSets[1].nftLock.symbol(),
            tokenParameters[1].veTokenSymbol,
            "Incorrect veTokenSymbol"
        );

        // PLUGIN REPO's

        PluginRepo.Version memory version;

        // Multisig code
        version = multisigPluginRepo.getLatestVersion(1);
        assertEq(
            address(multisigPluginSetup.implementation()),
            address(deployment.multisigPlugin.implementation()),
            "Invalid multisigPluginSetup"
        );

        // Gauge voter plugin
        assertNotEq(
            address(deployment.gaugeVoterPluginRepo),
            address(0),
            "Empty gaugeVoterPluginRepo field"
        );
        assertEq(deployment.gaugeVoterPluginRepo.latestRelease(), 1, "Invalid latestRelease");
        assertEq(deployment.gaugeVoterPluginRepo.buildCount(1), 1, "Invalid buildCount");
        version = deployment.gaugeVoterPluginRepo.getLatestVersion(1);
        assertEq(
            address(version.pluginSetup),
            address(gaugeVoterPluginSetup),
            "Invalid gaugeVoterPluginSetup"
        );
    }

    function test_StandardDeployment_2() public {
        address[] memory multisigMembers = new address[](13);
        for (uint256 i = 0; i < 13; i++) {
            multisigMembers[i] = address(uint160(i + 10));
        }

        PluginRepoFactory pRefoFactory = new PluginRepoFactory(
            PluginRepoRegistry(address(new MockPluginRepoRegistry()))
        );

        // Publish repo
        MultisigPluginSetup multisigPluginSetup = new MultisigPluginSetup();
        PluginRepo multisigPluginRepo = PluginRepoFactory(pRefoFactory)
            .createPluginRepoWithFirstVersion(
                "multisig-2-subdomain",
                address(multisigPluginSetup),
                address(this),
                " ",
                " "
            );

        SimpleGaugeVoterSetup gaugeVoterPluginSetup = new SimpleGaugeVoterSetup(
            address(new SimpleGaugeVoter()),
            address(new QuadraticIncreasingEscrow()),
            address(new ExitQueue()),
            address(new VotingEscrow()),
            address(new Clock()),
            address(new Lock())
        );

        TokenParameters[] memory tokenParameters = new TokenParameters[](3);
        tokenParameters[0] = TokenParameters({
            token: address(deployMockERC20("T3", "T3", 18)),
            veTokenName: "Name 3",
            veTokenSymbol: "TK3"
        });
        tokenParameters[1] = TokenParameters({
            token: address(deployMockERC20("T4", "T4", 18)),
            veTokenName: "Name 4",
            veTokenSymbol: "TK4"
        });
        tokenParameters[2] = TokenParameters({
            token: address(deployMockERC20("T5", "T5", 18)),
            veTokenName: "Name 5",
            veTokenSymbol: "TK5"
        });

        // PSP with voter plugin setup and multisig
        MockPluginSetupProcessorMulti psp;
        {
            address[] memory pluginSetups = new address[](4);
            pluginSetups[0] = address(gaugeVoterPluginSetup); // Token 1
            pluginSetups[1] = address(gaugeVoterPluginSetup); // Token 2
            pluginSetups[2] = address(gaugeVoterPluginSetup); // Token 3
            pluginSetups[3] = address(multisigPluginSetup);

            psp = new MockPluginSetupProcessorMulti(pluginSetups);
        }
        MockDAOFactory daoFactory = new MockDAOFactory(MockPluginSetupProcessor(address(psp)));

        DeploymentParameters memory creationParams = DeploymentParameters({
            // Multisig settings
            minApprovals: 5,
            multisigMembers: multisigMembers,
            // Gauge Voter
            tokenParameters: tokenParameters,
            feePercent: 0.2 ether,
            warmupPeriod: 5678,
            cooldownPeriod: 6789,
            minLockDuration: 7890,
            votingPaused: true,
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
                deployment.multisigPlugin.isMember(address(uint160(i + 10))),
                false,
                "Should not be a member"
            );
        }
        {
            (bool onlyListed, uint16 minApprovals) = deployment.multisigPlugin.multisigSettings();

            assertEq(onlyListed, true, "Invalid onlyListed");
            assertEq(minApprovals, 5, "Invalid minApprovals");
        }

        // Gauge voter plugin

        assertEq(
            deployment.gaugeVoterPluginSets.length,
            3,
            "Incorrect gaugeVoterPluginSets length"
        );
        // 0
        assertNotEq(
            address(deployment.gaugeVoterPluginSets[0].plugin),
            address(0),
            "Empty plugin address"
        );
        assertEq(deployment.gaugeVoterPluginSets[0].plugin.paused(), true, "Should be paused");
        assertNotEq(
            address(deployment.gaugeVoterPluginSets[0].curve),
            address(0),
            "Empty curve address"
        );
        assertEq(
            deployment.gaugeVoterPluginSets[0].curve.warmupPeriod(),
            5678,
            "Incorrect warmupPeriod"
        );
        assertNotEq(
            address(deployment.gaugeVoterPluginSets[0].exitQueue),
            address(0),
            "Empty exitQueue address"
        );
        assertEq(
            deployment.gaugeVoterPluginSets[0].exitQueue.feePercent(),
            0.2 ether,
            "Incorrect feePercent"
        );
        assertEq(
            deployment.gaugeVoterPluginSets[0].exitQueue.cooldown(),
            6789,
            "Incorrect cooldown"
        );
        assertEq(deployment.gaugeVoterPluginSets[0].exitQueue.minLock(), 7890, "Incorrect minLock");
        assertNotEq(
            address(deployment.gaugeVoterPluginSets[0].votingEscrow),
            address(0),
            "Empty votingEscrow address"
        );
        assertNotEq(
            address(deployment.gaugeVoterPluginSets[0].clock),
            address(0),
            "Empty clock address"
        );
        assertNotEq(
            address(deployment.gaugeVoterPluginSets[0].nftLock),
            address(0),
            "Empty nftLock address"
        );
        assertEq(
            deployment.gaugeVoterPluginSets[0].nftLock.name(),
            tokenParameters[0].veTokenName,
            "Incorrect veTokenName"
        );
        assertEq(
            deployment.gaugeVoterPluginSets[0].nftLock.symbol(),
            tokenParameters[0].veTokenSymbol,
            "Incorrect veTokenSymbol"
        );
        // 1
        assertNotEq(
            address(deployment.gaugeVoterPluginSets[1].plugin),
            address(0),
            "Empty plugin address"
        );
        assertEq(deployment.gaugeVoterPluginSets[1].plugin.paused(), true, "Should be paused");
        assertNotEq(
            address(deployment.gaugeVoterPluginSets[1].curve),
            address(0),
            "Empty curve address"
        );
        assertEq(
            deployment.gaugeVoterPluginSets[1].curve.warmupPeriod(),
            5678,
            "Incorrect warmupPeriod"
        );
        assertNotEq(
            address(deployment.gaugeVoterPluginSets[1].exitQueue),
            address(0),
            "Empty exitQueue address"
        );
        assertEq(
            deployment.gaugeVoterPluginSets[1].exitQueue.feePercent(),
            0.2 ether,
            "Incorrect feePercent"
        );
        assertEq(
            deployment.gaugeVoterPluginSets[1].exitQueue.cooldown(),
            6789,
            "Incorrect cooldown"
        );
        assertEq(deployment.gaugeVoterPluginSets[1].exitQueue.minLock(), 7890, "Incorrect minLock");
        assertNotEq(
            address(deployment.gaugeVoterPluginSets[1].votingEscrow),
            address(0),
            "Empty votingEscrow address"
        );
        assertNotEq(
            address(deployment.gaugeVoterPluginSets[1].clock),
            address(0),
            "Empty clock address"
        );
        assertNotEq(
            address(deployment.gaugeVoterPluginSets[1].nftLock),
            address(0),
            "Empty nftLock address"
        );
        assertEq(
            deployment.gaugeVoterPluginSets[1].nftLock.name(),
            tokenParameters[1].veTokenName,
            "Incorrect veTokenName"
        );
        assertEq(
            deployment.gaugeVoterPluginSets[1].nftLock.symbol(),
            tokenParameters[1].veTokenSymbol,
            "Incorrect veTokenSymbol"
        );
        // 2
        assertNotEq(
            address(deployment.gaugeVoterPluginSets[2].plugin),
            address(0),
            "Empty plugin address"
        );
        assertEq(deployment.gaugeVoterPluginSets[2].plugin.paused(), true, "Should be paused");
        assertNotEq(
            address(deployment.gaugeVoterPluginSets[2].curve),
            address(0),
            "Empty curve address"
        );
        assertEq(
            deployment.gaugeVoterPluginSets[2].curve.warmupPeriod(),
            5678,
            "Incorrect warmupPeriod"
        );
        assertNotEq(
            address(deployment.gaugeVoterPluginSets[2].exitQueue),
            address(0),
            "Empty exitQueue address"
        );
        assertEq(
            deployment.gaugeVoterPluginSets[2].exitQueue.feePercent(),
            0.2 ether,
            "Incorrect feePercent"
        );
        assertEq(
            deployment.gaugeVoterPluginSets[2].exitQueue.cooldown(),
            6789,
            "Incorrect cooldown"
        );
        assertEq(deployment.gaugeVoterPluginSets[2].exitQueue.minLock(), 7890, "Incorrect minLock");
        assertNotEq(
            address(deployment.gaugeVoterPluginSets[2].votingEscrow),
            address(0),
            "Empty votingEscrow address"
        );
        assertNotEq(
            address(deployment.gaugeVoterPluginSets[2].clock),
            address(0),
            "Empty clock address"
        );
        assertNotEq(
            address(deployment.gaugeVoterPluginSets[2].nftLock),
            address(0),
            "Empty nftLock address"
        );
        assertEq(
            deployment.gaugeVoterPluginSets[2].nftLock.name(),
            tokenParameters[2].veTokenName,
            "Incorrect veTokenName"
        );
        assertEq(
            deployment.gaugeVoterPluginSets[2].nftLock.symbol(),
            tokenParameters[2].veTokenSymbol,
            "Incorrect veTokenSymbol"
        );

        // PLUGIN REPO's

        PluginRepo.Version memory version;

        // Multisig code
        version = multisigPluginRepo.getLatestVersion(1);
        assertEq(
            address(multisigPluginSetup.implementation()),
            address(deployment.multisigPlugin.implementation()),
            "Invalid multisigPluginSetup"
        );

        // Gauge voter plugin
        assertNotEq(
            address(deployment.gaugeVoterPluginRepo),
            address(0),
            "Empty gaugeVoterPluginRepo field"
        );
        assertEq(deployment.gaugeVoterPluginRepo.latestRelease(), 1, "Invalid latestRelease");
        assertEq(deployment.gaugeVoterPluginRepo.buildCount(1), 1, "Invalid buildCount");
        version = deployment.gaugeVoterPluginRepo.getLatestVersion(1);
        assertEq(
            address(version.pluginSetup),
            address(gaugeVoterPluginSetup),
            "Invalid gaugeVoterPluginSetup"
        );
    }

    function test_MultipleDeploysDoNothing() public {
        address[] memory multisigMembers = new address[](13);
        for (uint256 i = 0; i < 13; i++) {
            multisigMembers[i] = address(uint160(i + 10));
        }

        PluginRepoFactory pRefoFactory = new PluginRepoFactory(
            PluginRepoRegistry(address(new MockPluginRepoRegistry()))
        );

        // Publish repo
        MultisigPluginSetup multisigPluginSetup = new MultisigPluginSetup();
        PluginRepo multisigPluginRepo = PluginRepoFactory(pRefoFactory)
            .createPluginRepoWithFirstVersion(
                "multisig-2-subdomain",
                address(multisigPluginSetup),
                address(this),
                " ",
                " "
            );

        SimpleGaugeVoterSetup gaugeVoterPluginSetup = new SimpleGaugeVoterSetup(
            address(new SimpleGaugeVoter()),
            address(new QuadraticIncreasingEscrow()),
            address(new ExitQueue()),
            address(new VotingEscrow()),
            address(new Clock()),
            address(new Lock())
        );

        TokenParameters[] memory tokenParameters = new TokenParameters[](3);
        tokenParameters[0] = TokenParameters({
            token: address(deployMockERC20("T3", "T3", 18)),
            veTokenName: "Name 3",
            veTokenSymbol: "TK3"
        });
        tokenParameters[1] = TokenParameters({
            token: address(deployMockERC20("T4", "T4", 18)),
            veTokenName: "Name 4",
            veTokenSymbol: "TK4"
        });
        tokenParameters[2] = TokenParameters({
            token: address(deployMockERC20("T5", "T5", 18)),
            veTokenName: "Name 5",
            veTokenSymbol: "TK5"
        });

        // PSP with voter plugin setup and multisig
        MockPluginSetupProcessorMulti psp;
        {
            address[] memory pluginSetups = new address[](4);
            pluginSetups[0] = address(gaugeVoterPluginSetup); // Token 1
            pluginSetups[1] = address(gaugeVoterPluginSetup); // Token 2
            pluginSetups[2] = address(gaugeVoterPluginSetup); // Token 3
            pluginSetups[3] = address(multisigPluginSetup);

            psp = new MockPluginSetupProcessorMulti(pluginSetups);
        }
        MockDAOFactory daoFactory = new MockDAOFactory(MockPluginSetupProcessor(address(psp)));

        DeploymentParameters memory creationParams = DeploymentParameters({
            // Multisig settings
            minApprovals: 5,
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

        // ok
        factory.deployOnce();

        vm.expectRevert(abi.encodeWithSelector(GaugesDaoFactory.AlreadyDeployed.selector));
        factory.deployOnce();

        vm.expectRevert(abi.encodeWithSelector(GaugesDaoFactory.AlreadyDeployed.selector));
        factory.deployOnce();
    }
}
