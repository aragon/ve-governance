
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "test/constants.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {
    Multisig,
    MultisigSetup as MultisigPluginSetup
} from "@aragon/osx/plugins/governance/multisig/MultisigSetup.sol";
import {CurveConstantLib} from "@libs/CurveConstantLib.sol";
import {PermissionLib} from "@aragon/osx/core/permission/PermissionLib.sol";

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
    IVotingEscrowCoreErrors,
    IVotingEscrowEventsStorageErrorsEvents,
    IExitMinLockCooldownErrorsAndEvents
} from "test/v1_3_0/versions.sol";
import {
    UpgradeGaugesFactoryV1_0_0__V1_3_0 as UpgradeFactory,
    Deployment as DeploymentUpgrade,
    DeploymentParameters as DeploymentParametersUpgrade,
    GaugePluginSet as GaugePluginSetUpgrade
} from "@factory/upgrades/UpgradeFactory_v1_0_0__v1_3_0.sol";

import {Upgrades} from "@foundry-upgrades/LegacyUpgrades.sol";
import {Options} from "@foundry-upgrades/Options.sol";

import {console2 as console} from "forge-std/console2.sol";

import {FixedPointBase} from "../base/FixedPointBase.sol";

contract RegressionV1_0_0__to__V1_3_0_Fork is
    Test,
    IGaugeVote,
    IVotingEscrowEventsStorageErrorsEvents,
    IExitMinLockCooldownErrorsAndEvents,
    FixedPointBase
{
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

    address gauge = address(0x777);

    function setUp() public {
        address factoryAddr = vm.envOr("FACTORY_ADDRESS", address(0));

        if (factoryAddr == address(0)) {
            revert("Factory address not provided");
        }

        factory = GaugesDaoFactoryV1_0_0(factoryAddr);

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
        token = new MockERC20("Mock Token", "MTK", 18);
        vm.etch(escrow.token(), address(token).code);

        FixedPointBase.initialize(
            clock.epochDuration() * CurveConstantLib.MAX_EPOCHS,
            clock.checkpointInterval()
        );

        upgradeFactory = new UpgradeFactory(address(factory));

        MockERC20(escrow.token()).mint(address(this), 10000e18);
        MockERC20(escrow.token()).approve(address(escrow), 10000e18);

        // We don't know when fork test runs,
        // so move to next epoch start to have a better idea.
        vm.warp(clock.resolveEpochStartTs(block.timestamp));

        vm.prank(address(dao));
        escrow.setMinDeposit(10e18);
    }

    function test_isWarmUp() public {
        vm.prank(address(dao));
        curve.setWarmupPeriod(3 days);

        vm.warp(block.timestamp + 3 days + 1 seconds);

        uint256 currentTs = block.timestamp;
        uint256 nextEpoch = clock.resolveEpochNextCheckpointTs(block.timestamp);

        uint256 tokenId = escrow.createLock(20e18);

        // Asserts before upgrade
        assertFalse(curve.isWarm(tokenId));

        vm.warp(nextEpoch);
        assertTrue(curve.isWarm(tokenId));

        uint256 vpBefore0 = _votingPowerAt(tokenId, nextEpoch, currentTs);
        uint256 vpBefore1 = _votingPowerAt(tokenId, nextEpoch + 1 seconds, currentTs);
        uint256 vpBefore2 = _votingPowerAt(tokenId, nextEpoch + maxTime + 1 seconds, currentTs);

        _upgrade();

        // Asserts after upgrade

        // Note that even though token was created before the upgrade,
        // we still treat it as its starting date to be from next epoch.
        // If we treat it as start of creation week's start ts,
        // voting powers wouldn't match before and after upgrade.
        // hence, even after the upgrade, token still should not be warm.
        assertFalse(curve.isWarm(tokenId));

        vm.warp(nextEpoch);
        assertTrue(curve.isWarm(tokenId));

        uint256 vpAfter0 = _votingPowerAt(tokenId, nextEpoch, currentTs);
        uint256 vpAfter1 = _votingPowerAt(tokenId, nextEpoch + 1 seconds, currentTs);
        uint256 vpAfter2 = _votingPowerAt(tokenId, nextEpoch + maxTime + 1 seconds, currentTs);

        assertEq(vpBefore0, vpAfter0);
        assertEq(vpBefore1, vpAfter1);
        assertEq(vpBefore2, vpAfter2);
    }

    function test_Exit() public {
        vm.startPrank(address(dao));
        curve.setWarmupPeriod(5 days);
        queue.setMinLock(5 days);
        queue.setCooldown(5 days);
        vm.stopPrank();

        // we start at sunday
        vm.warp(block.timestamp + 6 days);
        
        uint256 lockWrittenTs = block.timestamp;

        uint256 tokenId = escrow.createLock(20e18);
        lock.approve(address(escrow), tokenId);
        
        uint256 id = vm.snapshotState();
        _exitAssertions(tokenId, lockWrittenTs);

        // We revert the state so it's as if exit didn't happen.
        // This helps us to ensure that exact same asserts and 
        // exit work too after the upgrade.
        vm.revertTo(id);

        _upgrade();

        // It should work the same way after upgrade.
        _exitAssertions(tokenId, lockWrittenTs);
    }

    function _exitAssertions(uint256 _tokenId, uint256 _lockWrittenTs) private {
        vm.expectRevert(CannotExit.selector);
        escrow.beginWithdrawal(_tokenId);

        // we get to friday. 
        // next epoch already started and 5 days passed from writtenTs.
        vm.warp(block.timestamp + 5 days + 1 seconds);

        // we still can not exit because from `lock.start(which is _lockWrittenTs + 1 days)`, 
        // 5 days hasn't passed yet which is minLock requirement, 
        vm.expectRevert(
            abi.encodeWithSelector(
                MinLockNotReached.selector,
                _tokenId,
                5 days,
                _lockWrittenTs + 1 days + 5 days
            )
        );
        escrow.beginWithdrawal(_tokenId);

        // we get to saturday.
        vm.warp(block.timestamp + 1 days + 1 seconds);
        escrow.beginWithdrawal(_tokenId);

        // We should be able to exit 5 days from now.
        assertEq(queue.queue(_tokenId).exitDate, block.timestamp + 5 days);
        assertFalse(queue.canExit(_tokenId));

        vm.warp(block.timestamp + 5 days + 1 seconds);
        assertTrue(queue.canExit(_tokenId));
    }

     function _votingPowerAt(
        uint256 _tokenId,
        uint256 _at,
        uint256 _fallbackTs
    ) private returns (uint256 vp) {
        vm.warp(_at);
        vp = escrow.votingPower(_tokenId);
        vm.warp(_fallbackTs);
    }

    function _upgrade() private {
        vm.startPrank(address(dao));

        // simple upgrade for testing
        // deploy the new implementations
        PermissionLib.MultiTargetPermission[] memory grant0 = upgradeFactory.getPermissions(
            PermissionLib.Operation.Grant,
            0
        );

        PermissionLib.MultiTargetPermission[] memory revoke0 = upgradeFactory.getPermissions(
            PermissionLib.Operation.Revoke,
            0
        );

        PermissionLib.MultiTargetPermission[] memory grant1 = upgradeFactory.getPermissions(
            PermissionLib.Operation.Grant,
            1
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

    function onERC721Received(address, address, uint256, bytes memory) public pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
