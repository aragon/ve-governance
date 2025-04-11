pragma solidity ^0.8.17;

import {IGaugeVote} from "../../versions.sol";

import {EscrowBase} from "../../base/EscrowBase.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";

contract TestVotingWithDelegation is EscrowBase {
    address tokenOwner = address(this);

    address gauge = address(0x777);

    address alice = address(1);
    address bob = address(2);

    uint256[] tokenIds = new uint256[](2);

    function setUp() public override {
        super.setUp();

        super.mintAndApproveEscrow();

        tokenIds[0] = escrow.createLock(Lock_1_Amount);
        tokenIds[1] = escrow.createLock(Lock_2_Amount);

        nftLock.enableTransfers();

        // create a gauge
        voter.createGauge(gauge, "metadata");
    }

    /*//////////////////////////////////////////////////////////////
                      IVotes Delegate
    //////////////////////////////////////////////////////////////*/

    function test_Vote_Self_Delegating_Tokens() public {
        uint256 start = weekStartTs((block.timestamp));

        // make tokenOwner self delegatee
        ivotesAdapter.setAutoDelegation(true);
        ivotesAdapter.delegate(tokenOwner);

        assertEq(ivotesAdapter.numberOfDelegatedTokens(tokenOwner), 2);

        uint256 token1Bias = bias(Lock_1_Amount, block.timestamp - start);
        uint256 token2Bias = bias(Lock_2_Amount, block.timestamp - start);
        uint256 total = token1Bias + token2Bias;

        assertEq(ivotesAdapter.getVotes(tokenOwner), total);
        assertEq(voter.votes(tokenOwner, gauge), 0);

        vm.warp(clock.epochVoteStartTs());

        token1Bias = bias(Lock_1_Amount, block.timestamp - start);
        token2Bias = bias(Lock_2_Amount, block.timestamp - start);
        total = token1Bias + token2Bias;

        IGaugeVote.GaugeVote[] memory votes = new IGaugeVote.GaugeVote[](1);
        votes[0] = IGaugeVote.GaugeVote({gauge: gauge, weight: 1});

        vm.prank(tokenOwner);
        voter.vote(votes);

        assertEq(voter.votes(tokenOwner, gauge), total);
    }

    function test_Vote_Delegating_Tokens() public {
        uint256 start = weekStartTs((block.timestamp));

        // make tokenOwner self delegatee
        ivotesAdapter.setAutoDelegation(true);
        ivotesAdapter.delegate(alice);

        assertEq(ivotesAdapter.numberOfDelegatedTokens(tokenOwner), 2);

        uint256 token1Bias = bias(Lock_1_Amount, block.timestamp - start);
        uint256 token2Bias = bias(Lock_2_Amount, block.timestamp - start);
        uint256 total = token1Bias + token2Bias;

        assertEq(ivotesAdapter.getVotes(alice), total);

        vm.warp(clock.epochVoteStartTs());

        token1Bias = bias(Lock_1_Amount, block.timestamp - start);
        token2Bias = bias(Lock_2_Amount, block.timestamp - start);
        total = token1Bias + token2Bias;

        IGaugeVote.GaugeVote[] memory votes = new IGaugeVote.GaugeVote[](1);
        votes[0] = IGaugeVote.GaugeVote({gauge: gauge, weight: 1});

        assertEq(voter.votes(alice, gauge), 0);

        vm.prank(alice);
        voter.vote(votes);

        assertEq(voter.votes(alice, gauge), total);
    }

    function test_Vote_And_Transfer_Delegated_Tokens() public {
        address tokenReceiver = address(123);

        uint256 start = weekStartTs((block.timestamp));

        {
            // make Alice delegatee with tokenId = 1 and 2
            ivotesAdapter.delegate(alice);
            ivotesAdapter.delegate(tokenIds);
        }

        {
            // make Bob delegatee
            vm.prank(tokenReceiver);
            ivotesAdapter.delegate(bob);
        }

        assertEq(ivotesAdapter.numberOfDelegatedTokens(tokenOwner), 2);

        uint256 token1Bias = bias(Lock_1_Amount, block.timestamp - start);
        uint256 token2Bias = bias(Lock_2_Amount, block.timestamp - start);
        uint256 total = token1Bias + token2Bias;

        assertEq(ivotesAdapter.getVotes(alice), total);
        assertEq(ivotesAdapter.getVotes(bob), 0);

        vm.warp(clock.epochVoteStartTs());

        token1Bias = bias(Lock_1_Amount, block.timestamp - start);
        token2Bias = bias(Lock_2_Amount, block.timestamp - start);
        total = token1Bias + token2Bias;

        IGaugeVote.GaugeVote[] memory votes = new IGaugeVote.GaugeVote[](1);
        votes[0] = IGaugeVote.GaugeVote({gauge: gauge, weight: 1});

        assertEq(voter.votes(alice, gauge), 0);
        assertEq(voter.votes(bob, gauge), 0);

        vm.prank(alice);
        voter.vote(votes);

        assertEq(voter.votes(alice, gauge), total);
        assertEq(voter.votes(bob, gauge), 0);

        nftLock.transferFrom(address(this), tokenReceiver, tokenIds[0]);

        assertEq(ivotesAdapter.getVotes(alice), token2Bias);
        assertEq(ivotesAdapter.getVotes(bob), token1Bias);

        assertEq(voter.votes(alice, gauge), token2Bias);
        assertEq(voter.votes(bob, gauge), 0);

        vm.prank(tokenReceiver);
        nftLock.transferFrom(tokenReceiver, address(this), tokenIds[0]);

        assertEq(ivotesAdapter.getVotes(alice), total);
        assertEq(ivotesAdapter.getVotes(bob), 0);

        assertEq(voter.votes(alice, gauge), token2Bias);
        assertEq(voter.votes(bob, gauge), 0);
    }
}
