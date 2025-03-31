pragma solidity ^0.8.17;

import {console2 as console} from "forge-std/console2.sol";

import {Clock, QuadraticIncreasingEscrow, ILockedBalanceIncreasing, IVotingEscrowIncreasing as IVotingEscrow, IEscrowCurveIncreasing as IEscrowCurve} from "../../../versions.sol";
import {QuadraticCurveBase, MockEscrow} from "./QuadraticCurveBase.t.sol";

contract TestQuadraticIncreasingCurveLogic is QuadraticCurveBase {
    address attacker = address(0x1);
    error InvalidCheckpoint();

    function testUUPSUpgrade() public {
        address newImpl = address(new QuadraticIncreasingEscrow());
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

    function testCanWriteNewCheckpointsAtSameTime() public {
        vm.warp(1 weeks + 1 hours);

        LockedBalance memory first = LockedBalance({amount: 100, start: 1 weeks});
        LockedBalance memory second = LockedBalance({amount: 200, start: 1 weeks});

        escrow.checkpoint(1, LockedBalance(0, 0), first);
        escrow.checkpoint(1, first, second);

        // check we have only 1 token interval
        assertEq(curve.tokenPointIntervals(1), 1);
        assertEq(
            curve.tokenPointHistory(1, 1).coefficients[0],
            biasFP(100, 1 hours) + biasFP(200, 1 hours)
        );
        assertEq(curve.tokenPointHistory(1, 1).coefficients[1], slopeFP(200) + slopeFP(100));
    }
}
