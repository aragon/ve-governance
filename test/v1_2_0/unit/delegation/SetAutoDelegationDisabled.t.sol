pragma solidity ^0.8.17;

import {Base} from "./Base.sol";

contract TestSetAutoDelegationDisabled is Base {
    function setUp() public override {
        super.setUp();
    }

    function test_DisablesAutoDelegationAndEmitsTheEvent() public {
        address alice = address(123);
        address bob = address(456);

        // 1. alice disables it
        vm.prank(alice);
        vm.expectEmit();
        emit AutoDelegationDisabledSet(alice, true);
        dg.setAutoDelegationDisabled(true);

        // 2. only Alice's flag change, not bob
        assertTrue(dg.autoDelegationDisabled(alice));
        assertFalse(dg.autoDelegationDisabled(bob));

        // 3. Bob disables it
        vm.prank(bob);
        dg.setAutoDelegationDisabled(true);
        assertTrue(dg.autoDelegationDisabled(bob));

        // 4. Alice enables it, and only Alice's flag
        // should change, not bob.
        vm.prank(alice);
        dg.setAutoDelegationDisabled(false);
        assertFalse(dg.autoDelegationDisabled(alice));
        assertTrue(dg.autoDelegationDisabled(bob));
    }
}
