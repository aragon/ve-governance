pragma solidity ^0.8.17;

import {Base} from "./Base.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";

contract TestDelegate is Base {
    function setUp() public override {
        super.setUp();
    }

    event DelegateChanged(address indexed from, address indexed to, address indexed delegate);

    modifier AutoDelegationEnabled() {
        dg.setAutoDelegation(true);
        _;
    }

    /*//////////////////////////////////////////////////////////////
                      IVotes Delegate
    //////////////////////////////////////////////////////////////*/

    function test_Sets_Delegatee_Without_Delegating_Tokens() public {
        vm.expectEmit();
        emit DelegateChanged(sender, address(0), alice);

        dg.delegate(alice);

        assertEq(dg.delegates(sender), alice);
        assertEq(dg.numberOfDelegatedTokens(sender), 0);
    }

    function test_Delegates_owned_tokens_automatically() public AutoDelegationEnabled {
        _mockOwnedTokens(sender, singleId);
        _mockLocked(singleId[0], 100, weekStartTs(block.timestamp));

        dg.delegate(alice);

        assertEq(dg.numberOfDelegatedTokens(sender), 1);
    }

    function testRevert_CanNotDelegateToAnotherAddressIfTokenAlreadyDelegated() public {
        dg.delegate(alice);

        _mockLocked(singleId[0], 100, weekStartTs(block.timestamp));
        dg.delegate(singleId);

        vm.expectRevert(DelegationNotAllowed.selector);
        dg.delegate(bob);
    }

    function test_Updates_Delegatee() public {
        dg.delegate(alice);

        assertEq(dg.delegates(sender), alice);

        vm.expectEmit();
        emit DelegateChanged(sender, alice, bob);
        dg.delegate(bob);

        assertEq(dg.delegates(sender), bob);
    }

    /*//////////////////////////////////////////////////////////////
                    Delegate(uint256[] tokenIds)
    //////////////////////////////////////////////////////////////*/
    function testRevert_IfNoDelegateeIsSet() public {
        vm.expectRevert(DelegateeNotSet.selector);

        dg.delegate(singleId);
    }

    function testRevert_IfNotApprovedOrOwner() public {
        dg.delegate(alice);

        _mockApprovedOwner(false);

        vm.expectRevert(NotApprovedOrOwner.selector);
        dg.delegate(singleId);
    }

    function testRevert_IfTokenAlreadyDelegated() public {
        dg.delegate(alice);

        _mockLocked(singleId[0], 10, weekStartTs(block.timestamp));
        dg.delegate(singleId);

        vm.expectRevert(abi.encodeWithSelector(TokenAlreadyDelegated.selector, singleId[0]));

        dg.delegate(singleId);
    }

    function test_EmitsTheEvents() public {
        dg.delegate(alice);

        _mockLocked(multiIds[0], 10, weekStartTs(block.timestamp));
        _mockLocked(multiIds[1], 10, weekStartTs(block.timestamp));

        vm.expectEmit();
        emit TokensDelegated(sender, alice, multiIds);

        dg.delegate(multiIds);
    }

    function test_CorrectlySetsDelegatedTokenCount() public {
        dg.delegate(alice);
        uint256 start = weekStartTs((block.timestamp));

        _mockLocked(multiIds[0], 10, start);
        _mockLocked(multiIds[1], 10, start);
        dg.delegate(multiIds);

        assertEq(dg.numberOfDelegatedTokens(sender), multiIds.length);

        _mockLocked(3, 10, start);

        dg.delegate(getIds(3));

        assertEq(dg.numberOfDelegatedTokens(sender), multiIds.length + 1);
    }

    function test_SetsDelegatedTokenToTrue() public {
        dg.delegate(alice);
        _mockLocked(1, 10, weekStartTs((block.timestamp)));
        dg.delegate(getIds(1));

        assertEq(dg.tokenIsDelegated(1), true);
    }
}
