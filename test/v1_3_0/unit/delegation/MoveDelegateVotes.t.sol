pragma solidity ^0.8.17;

import {Base} from "./Base.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";

contract TestMoveDelegateVotes is Base {
    function setUp() public override {
        super.setUp();
    }

    function test_shouldRevertIfPaused() public {
        dg.pause();
        
        vm.expectRevert("Pausable: paused");
        dg.moveDelegateVotes(alice, bob, 1);
    }

    function testRevert_IfNotCalledByEscrow() public {
        vm.expectRevert(OnlyEscrow.selector);
        dg.moveDelegateVotes(alice, bob, 1);
    }

    function test_OnlyUpdatesFromDelegateeWhenToIsNotSet() public {
        address tokenOwner = address(567);
        uint256 start = weekStartTs((block.timestamp));

        {
            // make Alice delegate with tokenId = 1 and 2
            vm.startPrank(tokenOwner);
            dg.delegate(alice);
            _mockLocked(1, 10, start);
            _mockLocked(2, 15, start);
            dg.delegate(getIds(1, 2));
            vm.stopPrank();
        }

        uint256 token1Bias = bias(10, block.timestamp - start);
        uint256 token2Bias = bias(15, block.timestamp - start);
        uint256 total = token1Bias + token2Bias;

        assertEq(dg.getVotes(alice), total);
        assertEq(dg.getVotes(bob), 0);

        vm.prank(address(escrow));
        dg.moveDelegateVotes(tokenOwner, bob, 1);

        assertEq(dg.getVotes(alice), token2Bias);
        assertEq(dg.getVotes(bob), 0);
    }

    function test_OnlyUpdatesToDelegateeWhenFromIsNotSet() public {
        address tokenReceiver = address(567);
        vm.prank(tokenReceiver);
        dg.delegate(bob);

        _mockLocked(1, 10, weekStartTs((block.timestamp)));

        assertEq(dg.getVotes(bob), 0);

        vm.prank(address(escrow));
        dg.moveDelegateVotes(sender, tokenReceiver, 1);

        assertEq(dg.getVotes(bob), bias(10, block.timestamp - weekStartTs((block.timestamp))));
    }

    function test_UpdateBothDelegates() public {
        address tokenOwner = address(567);
        address tokenReceiver = address(678);

        uint256 start = weekStartTs((block.timestamp));
        _mockLocked(1, 10, start);
        _mockLocked(2, 15, start);

        {
            // make Alice delegatee with tokenId = 1 and 2
            vm.startPrank(tokenOwner);
            dg.delegate(alice);
            dg.delegate(getIds(1, 2));
            vm.stopPrank();
        }

        {
            // make Bob delegatee
            vm.prank(tokenReceiver);
            dg.delegate(bob);
        }

        uint256 token1Bias = bias(10, block.timestamp - start);
        uint256 token2Bias = bias(15, block.timestamp - start);
        uint256 total = token1Bias + token2Bias;

        assertEq(dg.getVotes(alice), total);
        assertEq(dg.getVotes(bob), 0);

        vm.prank(address(escrow));
        dg.moveDelegateVotes(tokenOwner, tokenReceiver, 1);

        assertEq(dg.getVotes(alice), token2Bias);
        assertEq(dg.getVotes(bob), token1Bias);
    }
}
