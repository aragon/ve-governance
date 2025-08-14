pragma solidity ^0.8.17;

import {Base} from "./Base.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";

contract TestSetDelegateAddress is Base {
    function setUp() public override {
        super.setUp();
    }

    event DelegateChanged(address indexed from, address indexed to, address indexed delegate);

    modifier AutoDelegationEnabled() {
        dg.setAutoDelegationDisabled(false);
        _;
    }

    function test_Sets_DelegateeForFirstTime() public {
        vm.expectEmit();
        emit DelegateChanged(sender, address(0), alice);

        dg.setDelegateAddress(alice);

        assertEq(dg.delegates(sender), alice);
        assertEq(dg.numberOfDelegatedTokens(sender), 0);
    }

    function test_Updates_Delegatee() public {
        dg.setDelegateAddress(alice);

        vm.expectEmit();
        emit DelegateChanged(sender, alice, bob);

        dg.setDelegateAddress(bob);

        assertEq(dg.delegates(sender), bob);
        assertEq(dg.numberOfDelegatedTokens(sender), 0);
    }

    function testRevert_CanNotDelegateToAnotherAddressIfTokenAlreadyDelegated() public {
        dg.setDelegateAddress(alice);

        _mockLocked(singleId[0], 100, weekStartTs(block.timestamp));
        dg.delegate(singleId);

        vm.expectRevert(DelegationNotAllowed.selector);
        dg.setDelegateAddress(bob);
    }
}
