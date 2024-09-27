pragma solidity ^0.8.17;

import {console2 as console} from "forge-std/console2.sol";

import {QuadraticIncreasingEscrow, IVotingEscrow, IEscrowCurve} from "src/escrow/increasing/QuadraticIncreasingEscrow.sol";
import {IVotingEscrowIncreasing, ILockedBalanceIncreasing} from "src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol";

import {QuadraticCurveBase, MockEscrow} from "./QuadraticCurveBase.t.sol";

contract TestQuadraticIncreasingCurve is QuadraticCurveBase {
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
        LockedBalance memory first = LockedBalance({amount: 100, start: 100});
        LockedBalance memory second = LockedBalance({amount: 200, start: 99});

        escrow.checkpoint(1, LockedBalance(0, 0), first);
        vm.expectRevert(InvalidCheckpoint.selector);
        escrow.checkpoint(1, first, second);
    }
}
