pragma solidity ^0.8.17;

import {IGaugeVote} from "../../versions.sol";

import {Base} from "./Base.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";

contract TestVotingWithDelegation_great is Base {
    address gauge = address(0x777);

    function setUp() public override {
        super.setUp();

        // create a gauge
        vm.startPrank(address(dao));
        voter.createGauge(gauge, "metadata");
    }

    /*//////////////////////////////////////////////////////////////
                      IVotes Delegate
    //////////////////////////////////////////////////////////////*/

    function test_Vote_Self_Delegating_Tokens() public {
        address tokenOwner = address(567);

        _mockOwnedTokens(tokenOwner, multiIds);

        uint256 start = weekStartTs((block.timestamp));
        _mockLocked(1, 10, start);
        _mockLocked(2, 15, start);

        {
            // make tokenOwner self delegatee
            vm.startPrank(tokenOwner);
            dg.setAutoDelegation(true);
            dg.delegate(tokenOwner);
            vm.stopPrank();
        }

        assertEq(dg.numberOfDelegatedTokens(tokenOwner), 2);

        uint256 token1Bias = bias(10, block.timestamp - start);
        uint256 token2Bias = bias(15, block.timestamp - start);
        uint256 total = token1Bias + token2Bias;

        assertEq(dg.getVotes(tokenOwner), total);
        assertEq(voter.votes(tokenOwner, gauge), 0);

        vm.warp(clock.epochVoteStartTs());

        IGaugeVote.GaugeVote[] memory votes = new IGaugeVote.GaugeVote[](1);
        votes[0] = IGaugeVote.GaugeVote({gauge: gauge, weight: 1});

        vm.prank(tokenOwner);
        voter.vote(votes);

        assertEq(voter.votes(tokenOwner, gauge), total);
    }

    function test_Vote_Delegating_Tokens() public {
        address tokenOwner = address(567);

        _mockOwnedTokens(tokenOwner, multiIds);

        uint256 start = weekStartTs((block.timestamp));
        _mockLocked(1, 10, start);
        _mockLocked(2, 15, start);

        {
            // make tokenOwner self delegatee
            vm.startPrank(tokenOwner);
            dg.setAutoDelegation(true);
            dg.delegate(alice);
            vm.stopPrank();
        }

        assertEq(dg.numberOfDelegatedTokens(tokenOwner), 2);

        uint256 token1Bias = bias(10, block.timestamp - start);
        uint256 token2Bias = bias(15, block.timestamp - start);
        uint256 total = token1Bias + token2Bias;

        assertEq(dg.getVotes(alice), total);

        vm.warp(clock.epochVoteStartTs());

        IGaugeVote.GaugeVote[] memory votes = new IGaugeVote.GaugeVote[](1);
        votes[0] = IGaugeVote.GaugeVote({gauge: gauge, weight: 1});

        assertEq(voter.votes(alice, gauge), 0);

        vm.prank(alice);
        voter.vote(votes);

        assertEq(voter.votes(alice, gauge), total);
    }

    function test_Vote_And_Transfer_Delegated_Tokens_ahahaha() public {
        address tokenOwner = address(567);
        address tokenReceiver = address(678);

        _mockOwnedTokens(tokenOwner, multiIds);

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

        assertEq(dg.numberOfDelegatedTokens(tokenOwner), 2);

        uint256 token1Bias = bias(10, block.timestamp - start);
        uint256 token2Bias = bias(15, block.timestamp - start);
        uint256 total = token1Bias + token2Bias;

        assertEq(dg.getVotes(alice), total);
        assertEq(dg.getVotes(bob), 0);

        vm.warp(clock.epochVoteStartTs());

        IGaugeVote.GaugeVote[] memory votes = new IGaugeVote.GaugeVote[](1);
        votes[0] = IGaugeVote.GaugeVote({gauge: gauge, weight: 1});

        assertEq(voter.votes(alice, gauge), 0);
        assertEq(voter.votes(bob, gauge), 0);

        vm.prank(alice);
        voter.vote(votes);

        assertEq(voter.votes(alice, gauge), total);
        assertEq(voter.votes(bob, gauge), 0);

        vm.prank(address(escrow));
        dg.moveDelegateVotes(tokenOwner, tokenReceiver, 1);

        assertEq(dg.getVotes(alice), token2Bias);
        assertEq(dg.getVotes(bob), token1Bias);

        assertEq(voter.votes(alice, gauge), token2Bias);
        assertEq(voter.votes(bob, gauge), 0);

        vm.prank(address(escrow));
        dg.moveDelegateVotes(tokenReceiver, tokenOwner, 1);

        assertEq(dg.getVotes(alice), total);
        assertEq(dg.getVotes(bob), 0);

        assertEq(voter.votes(alice, gauge), token2Bias);
        assertEq(voter.votes(bob, gauge), 0);
    }
}
