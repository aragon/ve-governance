pragma solidity ^0.8.17;

import {
    Clock,
    CurveConstantLib,
    Curve,
    ILockedBalanceDecreasing,
    IVotingEscrowDecreasing as IVotingEscrow,
    IEscrowCurveDecreasing as IEscrowCurve,
    IDeprecated
} from "../../../versions.sol";
import {CurveBase} from "./CurveBase.t.sol";
import {ProxyLib} from "@libs/ProxyLib.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract TestDecreasingCurveLogic is CurveBase {
    using SafeCast for int256;
    using SafeCast for uint256;

    address attacker = address(0x1);
    error InvalidCheckpoint();
    error CheckpointOnDepositIntervalNotAllowed();
    error InvalidLocks(
        uint256 tokenId,
        LockedBalanceDecreasing fromLocked,
        LockedBalanceDecreasing newLocked
    );

    function testUUPSUpgrade() public {
        (int256 constantCoefficient, int256 linearDenominator, uint256 maxEpochs) = CurveConstantLib.getParams();
        address newImpl = address(new Curve(constantCoefficient, linearDenominator, maxEpochs));
        curve.upgradeTo(newImpl);
        assertEq(curve.implementation(), newImpl);

        bytes memory err = _authErr(attacker, address(curve), curve.CURVE_ADMIN_ROLE());
        vm.prank(attacker);
        vm.expectRevert(err);
        curve.upgradeTo(newImpl);
    }

    function test_InitializeRevertsIfMaxTimeExceedsLoopLimit() public {
        uint256 loopLimit = 255;
        uint256 tooManyEpochs = loopLimit * clock.checkpointInterval() / clock.epochDuration() + 1;

        (int256 constantCoefficient, int256 linearDenominator, ) = CurveConstantLib.getParams();
        Curve impl = new Curve(constantCoefficient, linearDenominator, tooManyEpochs);
        bytes memory initCalldata = abi.encodeCall(
            Curve.initialize,
            (address(escrow), address(dao), address(clock))
        );

        // maxTime would be 256 weeks, more than one checkpoint's 255-interval loop can process.
        vm.expectRevert("maxTime exceeds checkpoint loop limit");
        ProxyLib.deployUUPSProxy(address(impl), initCalldata);
    }

    function testCannotWriteNewCheckpointInPast() public {
        vm.warp(2 weeks + 1 hours);

        LockedBalanceDecreasing memory first = _lockedBalanceToDecreasing(100, 2 weeks);
        LockedBalanceDecreasing memory second = _lockedBalanceToDecreasing(200, 1 weeks);

        escrow.checkpoint(1, _getEmptyLockedBalance(), first);
        vm.expectRevert(InvalidCheckpoint.selector);
        escrow.checkpoint(1, first, second);
    }

    function testCanWritenewCheckpointAtWeekBoundary() public {
        vm.warp(3 weeks);

        escrow.checkpoint(1, _getEmptyLockedBalance(), _lockedBalanceToDecreasing(100, 3 weeks));
    }

    function testCanCheckpointWithDifferentStartDates() public {
        vm.warp(2 weeks + 1 hours);

        LockedBalanceDecreasing memory first = _lockedBalanceToDecreasing(100, 2 weeks);
        LockedBalanceDecreasing memory second = _lockedBalanceToDecreasing(200, 2 weeks + 1 hours);

        // The escrow is responsible for ensuring valid lock transitions (e.g. via canMerge).
        // The curve itself allows checkpointing with different start dates to support
        // increaseUnlockTime and other legitimate operations.
        escrow.checkpoint(1, first, second);
    }

    function testCanWriteNewCheckpointsAtSameTime() public {
        vm.warp(1 weeks + 1 hours);

        LockedBalanceDecreasing memory first = _lockedBalanceToDecreasing(100, 1 weeks);
        LockedBalanceDecreasing memory second = _lockedBalanceToDecreasing(300, 1 weeks);

        escrow.checkpoint(1, _getEmptyLockedBalance(), first);
        escrow.checkpoint(1, first, second);

        // check we have only 1 token interval
        assertEq(curve.tokenPointIntervals(1), 1);
        assertEq(curve.tokenPointHistory(1, 1).bias.toInt256(), biasFP(second.lockedBalance.amount, 0));
        assertEq(curve.tokenPointHistory(1, 1).slope, slopeFP(second.lockedBalance.amount));
    }

    // The global point history can stall for more than 255 checkpoint
    // intervals (~5 years with weekly checkpoints) if no lock operation
    // happens. When the next checkpoint finally arrives, the global
    // advance loop hits its 255-iteration cap and must still record the
    // new lock at its real effective start instead of the stale
    // `staleTs + 255 intervals` timestamp. Otherwise `supplyAt` decays
    // the new lock's bias too early and under-reports the total voting
    // power from then on.
    // Found by `invariant_SumOfNftsAmountsEqualTotalLocked`.
    function test_CheckpointAfterMoreThan255IdleIntervals_KeepsSupplyInSyncWithTokens() public {
        // Token 1 becomes effective at week 3.
        vm.warp(2 weeks + 1 hours);
        uint256 start1 = weekStartTs(block.timestamp);
        escrow.checkpoint(1, _getEmptyLockedBalance(), _lockedBalanceToDecreasing(100e18, uint48(start1)));

        // The system stays untouched for 260 intervals (more than the
        // 255-iteration cap of the global advance loop), so the global history
        // stalls at `start1`. Token 1 expires in the meantime.
        uint256 start2 = start1 + 260 weeks;
        vm.warp(start2 + 1 hours);

        // Token 2 is created while the global history is stale.
        escrow.checkpoint(2, _getEmptyLockedBalance(), _lockedBalanceToDecreasing(50e18, uint48(start2)));

        // The total voting power must equal the sum of the token powers
        // (token 1 expired long ago, so only token 2 counts).
        vm.warp(start2 + 1 weeks);
        assertEq(curve.votingPowerAt(1, block.timestamp), 0, "token 1 should be expired");
        assertEq(
            curve.supplyAt(block.timestamp),
            curve.votingPowerAt(2, block.timestamp),
            "supply must equal sum of token powers"
        );
        assertEq(curve.supplyAt(block.timestamp), bias(50e18, block.timestamp - start2));
    }

    // Permanent locks must keep their (non-decaying) bias when the
    // global history is fast-forwarded after more than 255 idle
    // intervals.
    function test_CheckpointAfterMoreThan255IdleIntervals_KeepsPermanentLockBias() public {
        vm.warp(2 weeks + 1 hours);
        uint256 start1 = weekStartTs(block.timestamp);

        // A permanent lock (start == 0) with constant voting power, effective from week 3.
        escrow.checkpoint(
            1,
            _getEmptyLockedBalance(),
            LockedBalanceDecreasing(LockedBalance(40e18, 0), start1)
        );

        // A normal lock, effective from week 3 too.
        escrow.checkpoint(2, _getEmptyLockedBalance(), _lockedBalanceToDecreasing(50e18, uint48(start1)));

        // Idle for 260 intervals, then create token 3 while the history is stale.
        uint256 start2 = start1 + 260 weeks;
        vm.warp(start2 + 1 hours);
        escrow.checkpoint(3, _getEmptyLockedBalance(), _lockedBalanceToDecreasing(60e18, uint48(start2)));

        vm.warp(start2 + 1 weeks);

        // The total supply must equal the sum of the individual powers: the
        // permanent lock keeps its bias, token 2 has expired and token 3
        // decays from its real effective start.
        assertEq(curve.votingPowerAt(2, block.timestamp), 0, "token 2 should be expired");
        assertEq(
            curve.supplyAt(block.timestamp),
            curve.votingPowerAt(1, block.timestamp) + curve.votingPowerAt(3, block.timestamp),
            "supply must equal sum of token powers"
        );
        assertEq(curve.votingPowerAt(1, block.timestamp), bias(40e18, 0), "permanent bias must be kept");
        assertEq(curve.votingPowerAt(3, block.timestamp), bias(60e18, block.timestamp - start2));
    }
}
