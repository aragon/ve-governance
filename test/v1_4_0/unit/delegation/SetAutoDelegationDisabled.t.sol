pragma solidity ^0.8.17;

import {Base} from "./Base.sol";

import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";

contract TestSetAutoDelegationDisabled is Base {
    function setUp() public override {
        super.setUp();
    }

    function test_revertIfNotAllowed() public {
        dao.revoke({
            _who: address(type(uint160).max),
            _where: address(dg),
            _permissionId: dg.DELEGATION_TOKEN_ROLE()
        });
        bytes memory data = abi.encodeWithSelector(
            DaoUnauthorized.selector,
            address(dao),
            address(dg),
            address(this),
            dg.DELEGATION_TOKEN_ROLE()
        );
        vm.expectRevert(data);
        dg.setAutoDelegationDisabled(true);
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
