// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "test/constants.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";
import {MockPluginSetupProcessor} from "@mocks/osx/MockPSP.sol";
import {MockPluginSetupProcessorMulti} from "@mocks/osx/MockPSPMulti.sol";
import {MockPluginRepoRegistry} from "@mocks/osx/MockPluginRepoRegistry.sol";
import {MockDAOFactory} from "@mocks/osx/MockDAOFactory.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginRepoRegistry} from "@aragon/osx/framework/plugin/repo/PluginRepoRegistry.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {Addresslist} from "@aragon/osx/plugins/utils/Addresslist.sol";
import {Multisig, MultisigSetup as MultisigPluginSetup} from "@aragon/osx/plugins/governance/multisig/MultisigSetup.sol";

import {SimpleGaugeVoterSetup, IGaugeVote, VotingEscrow, Clock, Lock, QuadraticIncreasingEscrow, ExitQueue, SimpleGaugeVoter, GaugesDaoFactory as GaugesDaoFactoryV1_1_0, Deployment, DeploymentParameters, TokenParameters, GaugePluginSet} from "test/v1_1_0/versions.sol";
import {SimpleGaugeVoter as SimpleGaugeVoterV1_2_0} from "test/v1_2_0/versions.sol";

import {Upgrades} from "@foundry-upgrades/LegacyUpgrades.sol";
import {Options} from "@foundry-upgrades/Options.sol";

contract RegressionV1_1_0__to__V1_2_0 is Test, IGaugeVote {
    GaugesDaoFactoryV1_1_0 factory;

    VotingEscrow escrow;
    SimpleGaugeVoter voter;
    Clock clock;
    Lock lock;
    ExitQueue queue;
    QuadraticIncreasingEscrow curve;
    DAO dao;
    Multisig multisig;
    MockERC20 token;

    uint aliceToken;
    uint bobToken;
    uint carolToken;
    uint davidToken;
    uint aliceSecondToken;

    address gauge = address(0x777);

    uint256 bobVPSnapshot;
    uint256 aliceVPSnapshot;

    function setUp() public {
        vm.warp(1);
        vm.roll(1);

        factory = _deployViaFactory();
        Deployment memory deployment = factory.getDeployment();
        GaugePluginSet memory pluginSet = deployment.gaugeVoterPluginSets[0];

        // deconstruct the plugin set
        escrow = VotingEscrow(pluginSet.votingEscrow);
        voter = SimpleGaugeVoter(pluginSet.plugin);
        clock = Clock(pluginSet.clock);
        lock = Lock(pluginSet.nftLock);
        queue = ExitQueue(pluginSet.exitQueue);
        curve = QuadraticIncreasingEscrow(pluginSet.curve);
        dao = DAO(deployment.dao);
        multisig = Multisig(deployment.multisigPlugin);
        token = MockERC20(escrow.token());

        // setup gauge and unpause the voter
        vm.startPrank(address(dao));
        {
            voter.createGauge(gauge, "metadata");
        }
        vm.stopPrank();

        // mint some tokens
        token.mint(address(this), 10_000 ether);
        token.approve(address(escrow), 10_000 ether);

        aliceToken = escrow.createLockFor(1_000 ether, ALICE_ADDRESS);
        bobToken = escrow.createLockFor(1_000 ether, BOB_ADDRESS);
        carolToken = escrow.createLockFor(1_000 ether, CAROL_ADDRESS);
        davidToken = escrow.createLockFor(1_000 ether, DAVID_ADDRESS);

        // bob votes
        vm.warp(2 weeks + 3601);

        vm.startPrank(BOB_ADDRESS);
        {
            GaugeVote[] memory vote = new GaugeVote[](1);
            vote[0] = GaugeVote(1, gauge);
            bobVPSnapshot = escrow.votingPower(bobToken);
            voter.vote(bobToken, vote);
        }
        vm.stopPrank();

        // carol begins unstaking
        vm.startPrank(CAROL_ADDRESS);
        {
            lock.approve(address(escrow), carolToken);
            escrow.beginWithdrawal(carolToken);
        }
        vm.stopPrank();

        // wait a bit
        vm.warp(4 weeks);

        vm.startPrank(DAVID_ADDRESS);
        {
            lock.approve(address(escrow), davidToken);
            escrow.beginWithdrawal(davidToken);
        }
        vm.stopPrank();
    }

    function testValidateUpgradeGaugeVoter__v1_1_0__v1_2_0() public {
        Options memory options;

        string[] memory exclude = new string[](1);
        // disable initializers is invoked but the custom unsafe allow option is not set in the natspec
        exclude[0] = "lib/osx/packages/contracts/src/core/plugin/PluginUUPSUpgradeable.sol";
        options.exclude = exclude;

        // SimpleGaugeVoter can't be upgraded due to slot incompatibilities. Should always be a new deployment
        //options.referenceContract = "SimpleGaugeVoter_v1_1_0.sol";
        //Upgrades.validateUpgrade("SimpleGaugeVoter_v1_2_0.sol:SimpleGaugeVoterV1_2_0", options);

        options.referenceContract = "Clock.sol";
        Upgrades.validateUpgrade("Clock_v1_2_0.sol:ClockV1_2_0", options);

        options.referenceContract = "QuadraticIncreasingEscrow.sol";
        Upgrades.validateUpgrade("QuadraticIncreasingEscrow_v1_2_0.sol:QuadraticIncreasingEscrowV1_2_0", options);
    }

    function testInitialState() public view {
        // alice is locked and has voting power
        assertEq(escrow.locked(aliceToken).amount, 1_000 ether);
        assertGt(escrow.votingPower(aliceToken), 1_000 ether);

        // bob is locked and is currently voting
        assertEq(escrow.locked(bobToken).amount, 1_000 ether);
        assertTrue(voter.isVoting(bobToken));
        assertEq(voter.votes(bobToken, gauge), bobVPSnapshot);

        // carol is locked and can exit
        assertEq(escrow.locked(carolToken).amount, 1_000 ether);
        assertTrue(queue.canExit(carolToken));

        // david is locked and cannot exit
        assertEq(escrow.locked(davidToken).amount, 1_000 ether);
        assertFalse(queue.canExit(davidToken));
        assertEq(queue.ticketHolder(davidToken), DAVID_ADDRESS);
    }

    function testUpgrade() public {
        // simple upgrade for testing
        // deploy the new implementations
        // LockV1_2_0 lockV1_2_0 = new LockV1_2_0();
        // Lock lockV1_2_0 = new Lock();
        // SimpleGaugeVoterV1_2_0 voterV1_2_0 = new SimpleGaugeVoterV1_2_0();

        // upgrade the contracts
        vm.startPrank(address(dao));
        {
            // unsafe upgrade
            // lock.upgradeTo(address(lockV1_2_0));
            // voter.upgradeTo(address(voterV1_2_0));

            // safe upgrade
            _safeUpgradeVoter(address(voter));
        }
        vm.stopPrank();

        // retest the initial state
        testInitialState();

        // attempt to move through life cycle again
        // create new token for alice
        aliceSecondToken = escrow.createLockFor(1_000 ether, ALICE_ADDRESS);

        // move alice to voting
        vm.warp(6 weeks + 3601);
        vm.startPrank(ALICE_ADDRESS);
        {
            GaugeVote[] memory vote = new GaugeVote[](1);
            vote[0] = GaugeVote(1, gauge);
            voter.vote(aliceToken, vote);
            aliceVPSnapshot = escrow.votingPower(aliceToken);
        }
        vm.stopPrank();

        // move bob to exiting
        vm.startPrank(BOB_ADDRESS);
        {
            lock.approve(address(escrow), bobToken);
            escrow.resetVotesAndBeginWithdrawal(bobToken);
        }
        vm.stopPrank();

        // exit with carol
        vm.startPrank(CAROL_ADDRESS);
        {
            escrow.withdraw(carolToken);
        }
        vm.stopPrank();

        // validate the new state
        // alice2 is locked and has voting power
        assertEq(escrow.locked(aliceSecondToken).amount, 1_000 ether);
        assertGt(escrow.votingPower(aliceSecondToken), 1_000 ether);

        // alice1 is locked and is currently voting
        assertEq(escrow.locked(aliceToken).amount, 1_000 ether);
        assertTrue(voter.isVoting(aliceToken));
        assertEq(voter.votes(aliceToken, gauge), aliceVPSnapshot);

        // bob is locked and is currently exiting
        assertEq(escrow.locked(bobToken).amount, 1_000 ether);
        assertFalse(queue.canExit(bobToken));
        assertFalse(voter.isVoting(bobToken));
        assertEq(queue.ticketHolder(bobToken), BOB_ADDRESS);

        // carol is not locked and has her tokens back
        assertEq(escrow.locked(carolToken).amount, 0);
        assertEq(token.balanceOf(CAROL_ADDRESS), 950 ether); // sans fee

        // david is locked and can exit
        assertEq(escrow.locked(davidToken).amount, 1_000 ether);
        assertTrue(queue.canExit(davidToken));
    }

    ////////////////////////////////////////////////
    ///-------------- Internal ------------------///
    ////////////////////////////////////////////////

    function _safeUpgradeVoter(address _voter) internal {
        Options memory options;
        options.referenceContract = "SimpleGaugeVoter.sol";
        string[] memory exclude = new string[](1);
        // disable initializers is invoked but the custom unsafe allow option is not set in the natspec
        exclude[0] = "lib/osx/packages/contracts/src/core/plugin/PluginUUPSUpgradeable.sol";
        options.exclude = exclude;

        Upgrades.upgradeProxy(
            _voter,
            "SimpleGaugeVoter_v1_2_0.sol:SimpleGaugeVoterV1_2_0",
            "",
            options
        );
    }

    function _deployViaFactory() internal returns (GaugesDaoFactoryV1_1_0) {
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
            token: address(new MockERC20("T1", "T1", 18)),
            veTokenName: "Name 1",
            veTokenSymbol: "TK1"
        });
        tokenParameters[1] = TokenParameters({
            token: address(new MockERC20("T2", "T2", 18)),
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
            feePercent: 500, // 500 / 10_000 = 5%
            warmupPeriod: 1234,
            cooldownPeriod: 2345,
            minLockDuration: 3456,
            minDeposit: 1,
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

        GaugesDaoFactoryV1_1_0 _factory = new GaugesDaoFactoryV1_1_0(creationParams);

        _factory.deployOnce();

        vm.roll(block.number + 1); // mint one block
        return _factory;
    }
}
