pragma solidity ^0.8.17;

import {
    Clock,
    Curve,
    ILockedBalanceIncreasing,
    IVotingEscrowIncreasing as IVotingEscrow,
    IEscrowCurveIncreasing as IEscrowCurve,
    IDeprecated
} from "../../../versions.sol";
import {CurveBase} from "./CurveBase.t.sol";

contract TestQuadraticIncreasingCurveLogic is CurveBase {
    address attacker = address(0x1);
    error InvalidCheckpoint();
    error CheckpointOnDepositIntervalNotAllowed();
    error InvalidLocks(
        uint256 tokenId,
        ILockedBalanceIncreasing.LockedBalance fromLocked,
        ILockedBalanceIncreasing.LockedBalance newLocked
    );

    function testUUPSUpgrade() public {
        address newImpl = address(new Curve());
        curve.upgradeTo(newImpl);
        assertEq(curve.implementation(), newImpl);

        bytes memory err = _authErr(attacker, address(curve), curve.CURVE_ADMIN_ROLE());
        vm.prank(attacker);
        vm.expectRevert(err);
        curve.upgradeTo(newImpl);
    }

    function testCannotWriteNewCheckpointInPast() public {
        vm.warp(2 weeks + 1 hours);

        LockedBalance memory first = LockedBalance({amount: 100, start: 2 weeks});
        LockedBalance memory second = LockedBalance({amount: 200, start: 1 weeks});

        escrow.checkpoint(1, LockedBalance(0, 0), first);
        vm.expectRevert(InvalidCheckpoint.selector);
        escrow.checkpoint(1, first, second);
    }

    function testCannotWritenewCheckpointAtWeekBoundary() public {
        vm.warp(3 weeks);

        vm.expectRevert(CheckpointOnDepositIntervalNotAllowed.selector);
        escrow.checkpoint(1, LockedBalance(0, 0), LockedBalance({amount: 100, start: 3 weeks}));
    }

    function testCannotMergeIfNonMatureWithDifferentStartDates() public {
        vm.warp(2 weeks + 1 hours);

        LockedBalance memory first = LockedBalance({amount: 100, start: 2 weeks});
        LockedBalance memory second = LockedBalance({amount: 200, start: 2 weeks + 1});

        vm.expectRevert(abi.encodeWithSelector(InvalidLocks.selector, 1, first, second));
        escrow.checkpoint(1, first, second);
    }

    function testCanWriteNewCheckpointsAtSameTime() public {
        vm.warp(1 weeks + 1 hours);

        LockedBalance memory first = LockedBalance({amount: 100, start: 1 weeks});
        LockedBalance memory second = LockedBalance({amount: 200, start: 1 weeks});

        escrow.checkpoint(1, LockedBalance(0, 0), first);
        escrow.checkpoint(
            1,
            first,
            LockedBalance({amount: first.amount + second.amount, start: 1 weeks})
        );

        // check we have only 1 token interval
        assertEq(curve.tokenPointIntervals(1), 1);
        assertEq(
            curve.tokenPointHistory(1, 1).coefficients[0],
            biasFP(100, 1 hours) + biasFP(200, 1 hours)
        );
        assertEq(curve.tokenPointHistory(1, 1).coefficients[1], slopeFP(200) + slopeFP(100));
    }

    // bias functions use the 1e18 multiplier on the amount, so
    // passing higher than uint192 will result in an overflow.
    // This is not a problem in curve because in createLock:
    // amount.toUint208() * 1e18 is used and if overflow occurs,
    // lock would not be created in the first place, meaning that
    // only those locks are created that fit in, hence bias functions
    // on those amounts later on will be valid.
    function testFuzz_previewMaxBias(uint192 _amount) public view {
        assertEq(curve.previewMaxBias(_amount), bias(_amount, maxTime));
    }

    function testWarmupDeprecated() public {
        assertEq(curve.warmupPeriod(), 0);
        vm.expectRevert(IDeprecated.Deprecated.selector);
        curve.setWarmupPeriod(1 weeks);
    }
}
