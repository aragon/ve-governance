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
import {createERC1967Proxy} from "@aragon/osx/utils/Proxy.sol";
import {ENSSubdomainRegistrar} from "@aragon/osx/framework/utils/ens/ENSSubdomainRegistrar.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {Addresslist} from "@aragon/osx/plugins/utils/Addresslist.sol";
import {IPluginSetup} from "@aragon/osx/framework/plugin/setup/IPluginSetup.sol";
import {Multisig, MultisigSetup as MultisigPluginSetup} from "@aragon/osx/plugins/governance/multisig/MultisigSetup.sol";
import {hashHelpers, PluginSetupRef} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessorHelpers.sol";

import {SimpleGaugeVoterSetup, IGaugeVote, VotingEscrow, Clock, Lock, QuadraticIncreasingEscrow, ExitQueue, SimpleGaugeVoter, GaugesDaoFactory as GaugesDaoFactoryV1_1_0, Deployment, DeploymentParameters, TokenParameters, GaugePluginSet} from "test/v1_1_0/versions.sol";
import {
    ISimpleGaugeVoterSetupParams as ISimpleGaugeVoterSetupParamsV1_2_0,
    SimpleGaugeVoterSetup as SimpleGaugeVoterSetupV1_2_0,
    SimpleGaugeVoter as SimpleGaugeVoterV1_2_0,
    Clock as ClockV1_2_0,
    QuadraticIncreasingEscrow as QuadraticIncreasingEscrowV1_2_0
} from "test/v1_2_0/versions.sol";

import {UpgradeGaugesFactoryV1_2_0} from "src/factory/UpgradeGaugesFactory_v1_2_0.sol";

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {ProxyLib} from "@libs/ProxyLib.sol";

import {Upgrades} from "@foundry-upgrades/LegacyUpgrades.sol";
import {Options} from "@foundry-upgrades/Options.sol";

contract RegressionV1_1_0__to__V1_2_0 is Test, IGaugeVote {
    using Address for address;
    using Clones for address;
    using ERC165Checker for address;
    using ProxyLib for address;

    GaugesDaoFactoryV1_1_0 factory;
    UpgradeGaugesFactoryV1_2_0 upgradeFactory;

    GaugePluginSet[] oldPluginSets;
    GaugePluginSet[] pluginSets;

    SimpleGaugeVoterV1_2_0 voterV1_2_0;

    VotingEscrow escrow;
    SimpleGaugeVoter voter;
    Clock clock;
    Lock lock;
    ExitQueue queue;
    QuadraticIncreasingEscrow curve;

    DAO dao;
    Multisig multisig;
    MockERC20 token;

    PluginRepoFactory pluginRepoFactory;
    MockPluginSetupProcessor pluginSetupProcessor;

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
        DeploymentParameters memory parameters = factory.getDeploymentParameters();
        Deployment memory deployment = factory.getDeployment();

        for (uint i = 0; i < deployment.gaugeVoterPluginSets.length; i++) {
            oldPluginSets.push(deployment.gaugeVoterPluginSets[i]);
        }

        upgradeFactory = new UpgradeGaugesFactoryV1_2_0(factory);
        Deployment memory upgradeDeployment = upgradeFactory.getDeployment();

        for (uint i = 0; i < upgradeDeployment.gaugeVoterPluginSets.length; i++) {
            pluginSets.push(upgradeDeployment.gaugeVoterPluginSets[i]);
        }

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

        pluginRepoFactory = PluginRepoFactory(parameters.pluginRepoFactory);
        pluginSetupProcessor = MockPluginSetupProcessor(address(parameters.pluginSetupProcessor));
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
            // safe upgrade
            _safeUpgradeContracts();
        }
        vm.stopPrank();

        // setup gauge and unpause the voter
        vm.startPrank(address(dao));
        {
            voterV1_2_0.createGauge(gauge, "metadata");
        }
        vm.stopPrank();

        // retest the initial state
        testInitialState();

        assertFalse(voterV1_2_0.isVoting(aliceToken));
        assertFalse(voterV1_2_0.isVoting(bobToken));
        assertFalse(voterV1_2_0.isVoting(carolToken));
        assertFalse(voterV1_2_0.isVoting(davidToken));
        assertEq(voterV1_2_0.seasonTotalVotingPowerCast(0), 0);

        // attempt to move through life cycle again
        // create new token for alice
        aliceSecondToken = escrow.createLockFor(1_000 ether, ALICE_ADDRESS);

        // move alice to voting
        vm.warp(6 weeks + 3601);
        vm.startPrank(ALICE_ADDRESS);
        {
            GaugeVote[] memory vote = new GaugeVote[](1);
            vote[0] = GaugeVote(1, gauge);
            voterV1_2_0.vote(aliceToken, vote);
            aliceVPSnapshot = escrow.votingPower(aliceToken);
        }
        vm.stopPrank();

        // move bob to exiting
        vm.startPrank(BOB_ADDRESS);
        {
            lock.approve(address(escrow), bobToken);
            escrow.beginWithdrawal(bobToken);
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
        assertTrue(voterV1_2_0.isVoting(aliceToken));
        assertEq(voterV1_2_0.votes(aliceToken, gauge), aliceVPSnapshot);

        // bob is locked and is currently exiting
        assertEq(escrow.locked(bobToken).amount, 1_000 ether);
        assertFalse(queue.canExit(bobToken));
        assertFalse(voterV1_2_0.isVoting(bobToken));
        assertEq(queue.ticketHolder(bobToken), BOB_ADDRESS);

        // carol is not locked and has her tokens back
        assertEq(escrow.locked(carolToken).amount, 0);
        assertEq(token.balanceOf(CAROL_ADDRESS), 950 ether); // sans fee

        // david is locked and can exit
        assertEq(escrow.locked(davidToken).amount, 1_000 ether);
        assertTrue(queue.canExit(davidToken));

        assertEq(voterV1_2_0.seasonTotalVotingPowerCast(0), aliceVPSnapshot);
    }

    ////////////////////////////////////////////////
    ///-------------- Internal ------------------///
    ////////////////////////////////////////////////

    function _safeUpgradeContracts() internal {

        bytes32 rootPermissionID = dao.ROOT_PERMISSION_ID();

        dao.grant(address(dao), address(upgradeFactory), rootPermissionID);
        dao.grant(address(clock), address(upgradeFactory), clock.CLOCK_ADMIN_ROLE());
        dao.grant(address(curve), address(upgradeFactory), curve.CURVE_ADMIN_ROLE());

        Deployment memory deployment = factory.getDeployment();

        for(uint i = 0; i < deployment.gaugeVoterPluginSets.length; i++) {
            GaugePluginSet memory pluginSet = deployment.gaugeVoterPluginSets[i];
            dao.grant(address(pluginSet.clock), address(upgradeFactory), clock.CLOCK_ADMIN_ROLE());
            dao.grant(address(pluginSet.curve), address(upgradeFactory), curve.CURVE_ADMIN_ROLE());
        }

        upgradeFactory.upgrade();

        for(uint i = 0; i < deployment.gaugeVoterPluginSets.length; i++) {
            GaugePluginSet memory pluginSet = deployment.gaugeVoterPluginSets[i];
            dao.revoke(address(pluginSet.curve), address(upgradeFactory), curve.CURVE_ADMIN_ROLE());
            dao.revoke(address(pluginSet.clock), address(upgradeFactory), clock.CLOCK_ADMIN_ROLE());
        }

        dao.revoke(address(curve), address(upgradeFactory), curve.CURVE_ADMIN_ROLE());
        dao.revoke(address(clock), address(upgradeFactory), clock.CLOCK_ADMIN_ROLE());
        dao.revoke(address(dao), address(upgradeFactory), rootPermissionID);

        voterV1_2_0 = SimpleGaugeVoterV1_2_0(escrow.voter());

        assertNotEq(address(voterV1_2_0), address(voter));
    }

    function _deployViaFactory() internal returns (GaugesDaoFactoryV1_1_0) {
        address[] memory multisigMembers = new address[](13);
        for (uint256 i = 0; i < 13; i++) {
            multisigMembers[i] = address(uint160(i + 5));
        }

        MockPluginRepoRegistry registryBase = new MockPluginRepoRegistry();
        PluginRepoRegistry registry = PluginRepoRegistry(
            address(
                MockPluginRepoRegistry(
                    createERC1967Proxy(
                        address(registryBase),
                        abi.encodeWithSelector(MockPluginRepoRegistry.initialize.selector, dao)
                    )
                )
            )
        );

        PluginRepoFactory pRefoFactory = new PluginRepoFactory(registry);
        PluginSetupProcessor psp = new PluginSetupProcessor(registry);
        MockDAOFactory daoFactory = new MockDAOFactory(MockPluginSetupProcessor(address(psp)));

        // Publish repo
        MultisigPluginSetup multisigPluginSetup = new MultisigPluginSetup();

        PluginRepo multisigPluginRepo;
        vm.startPrank(address(dao));
        {
            multisigPluginRepo = pRefoFactory
                .createPluginRepoWithFirstVersion(
                    "multisig-subdomain",
                    address(multisigPluginSetup),
                    address(this),
                    " ",
                    " "
                );
        }
        vm.stopPrank();

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
            multisigPluginBuild: 1,
            // Voter plugin setup and ENS
            voterPluginSetup: gaugeVoterPluginSetup,
            voterEnsSubdomain: "gauge-ens-subdomain",
            // OSx addresses
            osxDaoFactory: address(daoFactory),
            pluginSetupProcessor: psp,
            pluginRepoFactory: pRefoFactory
        });

        GaugesDaoFactoryV1_1_0 _factory = new GaugesDaoFactoryV1_1_0(creationParams);

        _factory.deployOnce();

        vm.roll(block.number + 1); // mint one block
        return _factory;
    }
}
