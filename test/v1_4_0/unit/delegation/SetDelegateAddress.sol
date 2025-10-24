pragma solidity ^0.8.17;

import {Base} from "./Base.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";

contract TestSetDelegateAddress is Base {
    function setUp() public override {
        super.setUp();
    }

    event DelegateChanged(address indexed from, address indexed to, address indexed delegate);

    modifier AutoDelegationEnabled() {
        dg.setAutoDelegationDisabled(false);
        _;
    }

    function testRevert_IfNotAllowed() public {
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
        dg.setDelegateAddress(address(1));
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
