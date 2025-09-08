pragma solidity ^0.8.17;

import {Base} from "./Base.sol";

import {EscrowIVotesAdapter} from "../../versions.sol";
import {CurveConstantLib} from "@libs/CurveConstantLib.sol";

contract TestDelegateAdmin is Base {
    address attacker = address(1);

    function setUp() public override {
        super.setUp();
    }

    function testUUPSUpgrade() public {
        (int256[3] memory coefficients, uint256 maxEpoch) = CurveConstantLib.getCoefficients();
        address newImpl = address(new EscrowIVotesAdapter(coefficients, maxEpoch));
        
        dg.upgradeTo(newImpl);
        assertEq(dg.implementation(), newImpl);

        bytes memory err = _authErr(attacker, address(dg), dg.DELEGATION_ADMIN_ROLE());
        vm.prank(attacker);
        vm.expectRevert(err);
        dg.upgradeTo(newImpl);
    }

    function testPause() public {
        dg.pause();
        assertTrue(dg.paused());

        dg.unpause();
        assertFalse(dg.paused());

        bytes memory err = _authErr(attacker, address(dg), dg.DELEGATION_ADMIN_ROLE());
        vm.startPrank(attacker);
        {
            vm.expectRevert(err);
            dg.pause();

            vm.expectRevert(err);
            dg.unpause();
        }
        vm.stopPrank();
    }
}
