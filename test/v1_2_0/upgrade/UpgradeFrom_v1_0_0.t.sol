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
import {
    Multisig,
    MultisigSetup as MultisigPluginSetup
} from "@aragon/osx/plugins/governance/multisig/MultisigSetup.sol";
import {PermissionLib} from "@aragon/osx/core/permission/PermissionLib.sol";
import {CurveConstantLib} from "@libs/CurveConstantLib.sol";

import {
    GaugeVoterSetup,
    IGaugeVote,
    VotingEscrow,
    Clock,
    Lock,
    QuadraticIncreasingEscrow,
    ExitQueue,
    GaugeVoter as TokenGaugeVoter,
    GaugesDaoFactory as GaugesDaoFactoryV1_0_0,
    Deployment,
    DeploymentParameters,
    TokenParameters,
    GaugePluginSet
} from "test/v1_0_0/versions.sol";
import {
    Clock as ClockV1_2_0,
    Curve as LinearEscrowCurve,
    VotingEscrow as VotingEscrowV1_2_0,
    EscrowIVotesAdapter,
    Lock as LockV1_2_0,
    GaugeVoter as AddressGaugeVoter,
    IGaugeVote as IAddressGaugeVote,
    IVotingEscrowCoreErrors
} from "test/v1_2_0/versions.sol";
import {
    UpgradeGaugesFactoryV1_0_0__V1_2_0 as UpgradeFactory,
    Deployment as DeploymentUpgrade,
    DeploymentParameters as DeploymentParametersUpgrade,
    GaugePluginSet as GaugePluginSetUpgrade
} from "@factory/upgrades/UpgradeFactory_v1_0_0__v1_2_0.sol";

import {Upgrades} from "@foundry-upgrades/src/LegacyUpgrades.sol";
import {Options} from "@foundry-upgrades/src/Options.sol";


import {
    CachedViewCurve as CachedView,
    CachedViewArgumentsCurve as CachedViewArguments,
    fetchStateCurve as fetchState
} from "./CurveHelper.sol";

import {FixedPointBase} from "../base/FixedPointBase.sol";

contract RegressionV1_0_0__to__V1_2_0 is Test, IGaugeVote, FixedPointBase {
    GaugesDaoFactoryV1_0_0 factory;

    VotingEscrow escrow;

    TokenGaugeVoter tokenGaugeVoter;
    AddressGaugeVoter addressGaugeVoter;

    Clock clock;
    Lock lock;
    ExitQueue queue;
    QuadraticIncreasingEscrow curve;
    DAO dao;
    Multisig multisig;
    MockERC20 token;

    // upgraded implementations

    ClockV1_2_0 clockUpgrade;
    VotingEscrowV1_2_0 escrowUpgrade;
    LinearEscrowCurve curveUpgrade;
    LockV1_2_0 lockUpgrade;
    EscrowIVotesAdapter ivotesAdapter;
    UpgradeFactory upgradeFactory;

    uint aliceToken;
    uint bobToken;
    uint carolToken;
    uint davidToken;
    uint aliceSecondToken;

    address gauge = address(0x777);

    uint256 bobVPSnapshot;
    uint256 aliceVPSnapshot;

    CachedView vCache;
    CachedViewArguments args;

    function setUp() public {
        vm.warp(1);
        vm.roll(1);

        factory = _deployViaFactory();
        // upgradeFactory = new UpgradeFactory(address(factory));
        Deployment memory deployment = factory.getDeployment();
        GaugePluginSet memory pluginSet = deployment.gaugeVoterPluginSets[0];

        // deconstruct the plugin set
        escrow = VotingEscrow(pluginSet.votingEscrow);
        tokenGaugeVoter = TokenGaugeVoter(pluginSet.plugin);
        clock = Clock(pluginSet.clock);
        lock = Lock(pluginSet.nftLock);
        queue = ExitQueue(pluginSet.exitQueue);
        curve = QuadraticIncreasingEscrow(pluginSet.curve);
        dao = DAO(deployment.dao);
        multisig = Multisig(deployment.multisigPlugin);
        token = MockERC20(escrow.token());

        super.initialize(
            clock.epochDuration() * CurveConstantLib.MAX_EPOCHS,
            clock.checkpointInterval()
        );

        // setup gauge and unpause the voter
        vm.startPrank(address(dao));
        {
            tokenGaugeVoter.createGauge(gauge, "metadata");
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
            tokenGaugeVoter.vote(bobToken, vote);
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
        vm.warp(4 weeks + 1 seconds);

        vm.startPrank(DAVID_ADDRESS);
        {
            lock.approve(address(escrow), davidToken);
            escrow.beginWithdrawal(davidToken);
        }
        vm.stopPrank();

        args = CachedViewArguments({
            tokenId: aliceToken,
            timestamp: block.timestamp,
            amount: 1_000 ether,
            tokenInterval: 1,
            maturity: block.timestamp + maxTime,
            sampleTime: block.timestamp + 5 weeks
        });

        vCache = fetchState(curve, args);

        upgradeFactory = new UpgradeFactory(address(factory));
    }

    function testValidateUpgradeGaugeVoter_v1_0_0__v1_2_0() public {
        upgradeFactory.validateUpgrade();
    }

    function testInitialState() public view {
        // alice is locked and has voting power
        assertEq(escrow.locked(aliceToken).amount, 1_000 ether);
        assertVp(aliceToken, 1_000 ether);

        // bob is locked and is currently voting
        assertEq(escrow.locked(bobToken).amount, 1_000 ether);
        assertTrue(tokenGaugeVoter.isVoting(bobToken));
        assertEq(tokenGaugeVoter.votes(bobToken, gauge), bobVPSnapshot);

        // carol is locked and can exit
        assertEq(escrow.locked(carolToken).amount, 1_000 ether);
        assertTrue(queue.canExit(carolToken));

        // david is locked and cannot exit
        assertEq(escrow.locked(davidToken).amount, 1_000 ether);
        assertFalse(queue.canExit(davidToken));
        assertEq(queue.ticketHolder(davidToken), DAVID_ADDRESS);
    }

    function test_upgrade() public {
        uint256 vp0Before = escrow.votingPower(aliceToken);
        uint256 vp1Before = escrow.votingPower(bobToken);

        // upgrade contracts
        _upgrade();

        uint256 vp0After = escrow.votingPower(aliceToken);
        uint256 vp1After = escrow.votingPower(bobToken);

        // Test that voting powers are the same
        // before and after upgrade.
        assertEq(vp0Before, vp0After);
        assertEq(vp1Before, vp1After);

        // retest the initial state
        testInitialState();

        // attempt to move through life cycle again
        // create new token for alice
        aliceSecondToken = escrow.createLockFor(1_000 ether, ALICE_ADDRESS);

        // move alice to voting
        vm.warp(6 weeks + 3601);
        vm.startPrank(ALICE_ADDRESS);
        {
            ivotesAdapter.delegate(ALICE_ADDRESS);

            IAddressGaugeVote.GaugeVote[] memory vote = new IAddressGaugeVote.GaugeVote[](1);
            vote[0] = IAddressGaugeVote.GaugeVote(1, gauge);
            addressGaugeVoter.vote(vote);
            aliceVPSnapshot = escrow.votingPower(aliceToken) + escrow.votingPower(aliceSecondToken);
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
        assertVp(aliceSecondToken, 1_000 ether);

        // alice1 is locked and is currently voting
        assertEq(escrow.locked(aliceToken).amount, 1_000 ether);
        assertTrue(addressGaugeVoter.isVoting(ALICE_ADDRESS));
        assertEq(addressGaugeVoter.votes(ALICE_ADDRESS, gauge), aliceVPSnapshot);

        // bob is locked and is currently exiting
        assertEq(escrow.locked(bobToken).amount, 1_000 ether);
        assertFalse(queue.canExit(bobToken));
        assertFalse(addressGaugeVoter.isVoting(BOB_ADDRESS));
        assertEq(queue.ticketHolder(bobToken), BOB_ADDRESS);

        // carol is not locked and has her tokens back
        assertEq(escrow.locked(carolToken).amount, 0);
        assertEq(token.balanceOf(CAROL_ADDRESS), 950 ether); // sans fee

        // david is locked and can exit
        assertEq(escrow.locked(davidToken).amount, 1_000 ether);
        assertTrue(queue.canExit(davidToken));

        _compareCurveState();
    }

    function test_upgradeAndMerge() public {
        _upgrade();

        _mockApprovedOwner(address(this), aliceToken);
        _mockApprovedOwner(address(this), bobToken);

        escrowUpgrade = VotingEscrowV1_2_0(address(escrow));
        lockUpgrade = LockV1_2_0(address(lock));

        // merge tokens/locks that were created before the upgrade.
        // Note that we created locks(tokens) to different addresses.
        // It must be owned by the same address to do the merge.
        vm.expectRevert(IVotingEscrowCoreErrors.NotSameOwner.selector);
        escrowUpgrade.merge(aliceToken, bobToken);

        // Enable transfers of nfts, so alice can transfer it to bob
        // which would cause both tokens to have the same owner.
        // hence we can do the merge.
        vm.prank(address(dao));
        lockUpgrade.enableTransfers();

        vm.prank(ALICE_ADDRESS);
        lockUpgrade.transferFrom(ALICE_ADDRESS, BOB_ADDRESS, aliceToken);

        // we can do merge now, since both tokens have same owner(bob).
        escrowUpgrade.merge(aliceToken, bobToken);

        assertEq(escrowUpgrade.votingPower(aliceToken), 0);

        uint256 bobTokenVPAfterMerge = escrowUpgrade.votingPower(bobToken);

        uint256 start = escrowUpgrade.locked(bobToken).start;
        uint256 expectedVPAfterMerge = bias(1_000 ether, block.timestamp - start) +
            bias(1_000 ether, block.timestamp - start);

        assertEq(bobTokenVPAfterMerge, expectedVPAfterMerge);

        vm.startPrank(BOB_ADDRESS);
        ivotesAdapter.delegate(BOB_ADDRESS);
        vm.stopPrank();

        assertEq(ivotesAdapter.getVotes(BOB_ADDRESS), expectedVPAfterMerge);
    }

    function test_upgradeSplit() public {
        uint256 vpBeforeUpgrade = escrow.votingPower(aliceToken);

        _upgrade();

        _mockApprovedOwner(address(this), aliceToken);

        escrowUpgrade = VotingEscrowV1_2_0(address(escrow));

        vm.startPrank(address(dao));
        dao.grant(address(escrowUpgrade), address(this), escrowUpgrade.ESCROW_ADMIN_ROLE());
        vm.stopPrank();
        escrowUpgrade.enableSplit();

        // split the lock that were created before the upgrade.
        vm.prank(ALICE_ADDRESS);
        uint256 newTokenId = escrowUpgrade.split(aliceToken, 50 ether);

        uint256 vpAfterUpgradeAndSplit = escrowUpgrade.votingPower(aliceToken) +
            escrowUpgrade.votingPower(newTokenId);

        assertEq(vpBeforeUpgrade, vpAfterUpgradeAndSplit);
    }

    function _compareCurveState() internal view {
        CachedView memory vLatest = fetchState(curve, args);

        // 4. Assert all fields are unchanged
        assertEq(vCache.escrow, vLatest.escrow);
        assertEq(vCache.clock, vLatest.clock);
        assertEq(vCache.warmupPeriod, vLatest.warmupPeriod);

        assertEq(vCache.tokenPointInterval, vLatest.tokenPointInterval);
        assertEq(vCache.maxBias, vLatest.maxBias);
        assertEq(vCache.isWarm, vLatest.isWarm);
        assertEq(vCache.bias, vLatest.bias);
        assertEq(vCache.votingPower, vLatest.votingPower);

        for (uint i = 0; i < 3; i++) {
            assertEq(vCache.coefficientsPlain[i], vLatest.coefficientsPlain[i]);
        }

        assertEq(vCache.tokenPointHistory.bias, vLatest.tokenPointHistory.bias);
        assertEq(vCache.tokenPointHistory.checkpointTs, vLatest.tokenPointHistory.checkpointTs);
        assertEq(vCache.tokenPointHistory.writtenTs, vLatest.tokenPointHistory.writtenTs);

        // We also want to test that the voting power in the cache is unchanged over the sample
        assertEq(vCache.votingPowerSample, curve.votingPowerAt(args.tokenId, args.sampleTime));
        assertEq(vCache.votingPowerMaturity, curve.votingPowerAt(args.tokenId, args.maturity));
    }

    function _upgrade() private {
        vm.startPrank(address(dao));
        // simple upgrade for testing
        // deploy the new implementations
        PermissionLib.MultiTargetPermission[] memory grant0 = upgradeFactory.getPermissions(
            PermissionLib.Operation.Grant,
            0
        );
        PermissionLib.MultiTargetPermission[] memory grant1 = upgradeFactory.getPermissions(
            PermissionLib.Operation.Grant,
            1
        );
        PermissionLib.MultiTargetPermission[] memory revoke0 = upgradeFactory.getPermissions(
            PermissionLib.Operation.Revoke,
            0
        );

        PermissionLib.MultiTargetPermission[] memory revoke1 = upgradeFactory.getPermissions(
            PermissionLib.Operation.Revoke,
            1
        );

        // upgrade the contracts
        vm.startPrank(address(dao));
        {
            dao.applyMultiTargetPermissions(grant0);
            dao.applyMultiTargetPermissions(grant1);

            upgradeFactory.upgrade(
                false,
                new ClockV1_2_0(),
                new LinearEscrowCurve(),
                new VotingEscrowV1_2_0(),
                new LockV1_2_0(),
                new EscrowIVotesAdapter(),
                new AddressGaugeVoter()
            );

            DeploymentUpgrade memory deps = upgradeFactory.getDeployment();
            ivotesAdapter = deps.gaugeVoterPluginSets[0].delegation;
            addressGaugeVoter = deps.gaugeVoterPluginSets[0].plugin;

            dao.applyMultiTargetPermissions(revoke0);
            dao.applyMultiTargetPermissions(revoke1);

            dao.grant(
                address(addressGaugeVoter),
                address(dao),
                addressGaugeVoter.GAUGE_ADMIN_ROLE()
            );

            dao.grant(address(escrow), address(dao), escrow.PAUSER_ROLE());
            dao.grant(address(ivotesAdapter), address(dao), ivotesAdapter.DELEGATION_ADMIN_ROLE());

            // After the upgrade, these contracts are paused.
            // so we assert and then unpause, so tests can work.
            assertTrue(escrow.paused());
            assertTrue(ivotesAdapter.paused());
            assertTrue(addressGaugeVoter.paused());

            // unpause contracts.
            escrow.unpause();
            ivotesAdapter.unpause();
            addressGaugeVoter.unpause();

            // create gauge on the address gauge voter.
            addressGaugeVoter.createGauge(gauge, "metadata");
        }
        vm.stopPrank();
    }
    ////////////////////////////////////////////////
    ///-------------- Internal ------------------///
    ////////////////////////////////////////////////

    function _deployViaFactory() internal returns (GaugesDaoFactoryV1_0_0) {
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

        GaugeVoterSetup gaugeVoterPluginSetup = new GaugeVoterSetup(
            address(new TokenGaugeVoter()),
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

        GaugesDaoFactoryV1_0_0 _factory = new GaugesDaoFactoryV1_0_0(creationParams);

        _factory.deployOnce();

        vm.roll(block.number + 1); // mint one block
        return _factory;
    }

    function unpause() private {
        vm.startPrank(address(dao)); 
        dao.grant(address(escrow), address(this), escrow.PAUSER_ROLE());
        vm.stopPrank();
        escrow.unpause();
    }

    function _mockApprovedOwner(address _who, uint256 _tokenId) private {
        vm.mockCall(
            address(lock),
            abi.encodeWithSelector(lock.isApprovedOrOwner.selector, _who, _tokenId),
            abi.encode(true)
        );
    }

    function assertVp(uint256 _tokenId, uint256 _amount) private view {
        // if maxTime is 0, then vp is always constant.
        if (maxTime == 0) {
            assertEq(escrow.votingPower(_tokenId), _amount);
        } else {
            assertGt(escrow.votingPower(_tokenId), _amount);
        }
    }
}
