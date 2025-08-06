pragma solidity ^0.8.17;

import {EscrowBase, IAddressGaugeVote} from "../../base/EscrowBase.sol";
import {console2 as console} from "forge-std/console2.sol";

import {
    Clock,
    IClock,
    Lock,
    VotingEscrow,
    IVotingEscrowIncreasing,
    IEscrowCurveIncreasing,
    IVotingEscrowIncreasing,
    IVotingEscrowCoreErrors,
    IMerge,
    ISplit,
    ILockedBalanceIncreasing,
    IEscrowCurveGlobalStorage,
    IEscrowCurveTokenStorage,
    IEscrowCurveGlobalStorage
} from "../../versions.sol";

contract TestMerge_DelegationAndVoter is
    IEscrowCurveTokenStorage,
    IEscrowCurveGlobalStorage,
    EscrowBase
{
    address gauge = address(0x777);
    address alice = address(0x123);
    address bob = address(0x192);

    function setUp() public override {
        super.setUp();

        super.mintAndApproveEscrow(type(uint256).max);

        vm.warp(2 weeks + 1 hours + 1);
        voter.createGauge(gauge, "metadata");
        escrow.enableSplit();
    }

    function test_Merge_CorrectlyUpdatesDelegationAndVotes() public {
        uint256 amount1 = 15e18;
        uint256 amount2 = 20e18;

        token.transfer(alice, amount1 + amount2);

        // alice creates 2 locks(nfts), delegates to herself and votes.
        {
            vm.startPrank(alice);
            token.approve(address(escrow), amount1 + amount2);

            escrow.createLock(amount1);
            ivotesAdapter.delegate(alice);

            escrow.createLock(amount2);

            // vote
            IAddressGaugeVote.GaugeVote[] memory votes = new IAddressGaugeVote.GaugeVote[](1);
            votes[0] = IAddressGaugeVote.GaugeVote(100, gauge);
            voter.vote(votes);

            // approve so address(this) can call merge..
            nftLock.setApprovalForAll(address(this), true);

            vm.stopPrank();
        }

        uint256 checkpointTs = weekStartTs(block.timestamp);
        uint256 writtenTs = block.timestamp;

        // Assert pre-state before running merge.
        uint256 aliceBias = bias(amount1 + amount2, block.timestamp - checkpointTs);

        assertEq(voter.votes(alice, gauge), aliceBias);
        assertEq(ivotesAdapter.getVotes(alice), aliceBias);
        assertTrue(ivotesAdapter.tokenIsDelegated(1));
        assertTrue(ivotesAdapter.tokenIsDelegated(2));
        assertEq(ivotesAdapter.numberOfDelegatedTokens(alice), 2);

        // Run merge
        uint256 lockEnd = getEndTimestamp(checkpointTs, writtenTs);
        vm.warp(lockEnd + 1 seconds);
        escrow.merge(1, 2);

        // Assert state after merge..

        // Even though tokenId = 1 is burnt due to merge,
        // Alice still must not lose its power as that
        // token's amount is merged into another. Note that
        // bias must be recalculated as merge occured after maxTime,
        // so duration will be different.
        assertEq(ivotesAdapter.getVotes(alice), bias(amount1 + amount2, maxTime));

        // Gauge must still have the same power of Alice's recorded vote.
        // It's still `aliceBias` as we don't update the vote record on voter
        // if new voting power is greater than old one unless user re-votes manually.
        assertEq(voter.votes(alice, gauge), aliceBias);

        assertFalse(ivotesAdapter.tokenIsDelegated(1));
        assertTrue(ivotesAdapter.tokenIsDelegated(2));
        assertEq(ivotesAdapter.numberOfDelegatedTokens(alice), 1);
    }

    function testFuzz_Merge_WhenTokensAreNotDelegated_AndDelegateeNotSet(
        uint160 _amount1,
        uint160 _amount2
    ) public {
        _approve(_amount1, _amount2);

        vm.startPrank(alice);
        uint256 tokenId1 = escrow.createLock(_amount1);
        uint256 tokenId2 = escrow.createLock(_amount2);

        assertFalse(ivotesAdapter.tokenIsDelegated(tokenId1));
        assertFalse(ivotesAdapter.tokenIsDelegated(tokenId2));

        escrow.merge(tokenId1, tokenId2);
        assertEq(ivotesAdapter.getPastVotes(bob, block.timestamp), 0);

        assertFalse(ivotesAdapter.tokenIsDelegated(tokenId1));
        assertFalse(ivotesAdapter.tokenIsDelegated(tokenId2));
        assertEq(ivotesAdapter.numberOfDelegatedTokens(alice), 0);
        vm.stopPrank();
    }

    function testFuzz_Merge_WhenTokensAreNotDelegated_ButDelegateeSet(
        uint160 _amount1,
        uint160 _amount2
    ) public {
        _approve(_amount1, _amount2);

        vm.startPrank(alice);
        uint256 tokenId1 = escrow.createLock(_amount1);
        uint256 tokenId2 = escrow.createLock(_amount2);
        ivotesAdapter.setDelegateAddress(bob);

        assertFalse(ivotesAdapter.tokenIsDelegated(tokenId1));
        assertFalse(ivotesAdapter.tokenIsDelegated(tokenId2));

        escrow.merge(tokenId1, tokenId2);

        assertEq(ivotesAdapter.getPastVotes(bob, block.timestamp), 0);
        assertFalse(ivotesAdapter.tokenIsDelegated(tokenId1));
        assertFalse(ivotesAdapter.tokenIsDelegated(tokenId2));
        assertEq(ivotesAdapter.numberOfDelegatedTokens(alice), 0);
        vm.stopPrank();
    }

    function testFuzz_Merge_WhenBothTokensAreDelegated(uint160 _amount1, uint160 _amount2) public {
        _approve(_amount1, _amount2);

        vm.startPrank(alice);
        ivotesAdapter.setDelegateAddress(bob);
        uint256 tokenId1 = escrow.createLock(_amount1);
        uint256 tokenId2 = escrow.createLock(_amount2);

        assertTrue(ivotesAdapter.tokenIsDelegated(tokenId1));
        assertTrue(ivotesAdapter.tokenIsDelegated(tokenId2));

        uint256 pastVotesBefore = ivotesAdapter.getPastVotes(bob, block.timestamp);
        escrow.merge(tokenId1, tokenId2);
        uint256 pastVotesAfter = ivotesAdapter.getPastVotes(bob, block.timestamp);

        assertFalse(ivotesAdapter.tokenIsDelegated(tokenId1));
        assertTrue(ivotesAdapter.tokenIsDelegated(tokenId2));
        assertEq(ivotesAdapter.numberOfDelegatedTokens(alice), 1);
        assertEq(pastVotesBefore, pastVotesAfter);
        vm.stopPrank();
    }

    function testFuzz_Merge_WhenFromIsDelegatedAndToIsNot(
        uint160 _amount1,
        uint160 _amount2
    ) public {
        _approve(_amount1, _amount2);

        vm.startPrank(alice);
        uint256 tokenId1 = escrow.createLock(_amount1);

        ivotesAdapter.setDelegateAddress(bob);
        uint256 tokenId2 = escrow.createLock(_amount2);

        assertFalse(ivotesAdapter.tokenIsDelegated(tokenId1));
        assertTrue(ivotesAdapter.tokenIsDelegated(tokenId2));

        assertEq(
            ivotesAdapter.getPastVotes(bob, block.timestamp),
            bias(_amount2, block.timestamp - weekStartTs(block.timestamp))
        );
        escrow.merge(tokenId2, tokenId1);
        assertEq(
            ivotesAdapter.getPastVotes(bob, block.timestamp),
            bias(
                uint256(_amount1) + uint256(_amount2),
                block.timestamp - weekStartTs(block.timestamp)
            )
        );

        assertTrue(ivotesAdapter.tokenIsDelegated(tokenId1));
        assertFalse(ivotesAdapter.tokenIsDelegated(tokenId2));

        assertEq(ivotesAdapter.numberOfDelegatedTokens(alice), 1);
        vm.stopPrank();
    }

    function testFuzz_Merge_WhenFromIsNotDelegatedAndToIs(
        uint160 _amount1,
        uint160 _amount2
    ) public {
        _approve(_amount1, _amount2);

        vm.startPrank(alice);
        uint256 tokenId1 = escrow.createLock(_amount1);

        ivotesAdapter.setDelegateAddress(bob);
        uint256 tokenId2 = escrow.createLock(_amount2);

        assertEq(
            ivotesAdapter.getPastVotes(bob, block.timestamp),
            bias(_amount2, block.timestamp - weekStartTs(block.timestamp))
        );
        escrow.merge(tokenId1, tokenId2);
        assertEq(
            ivotesAdapter.getPastVotes(bob, block.timestamp),
            bias(
                uint256(_amount1) + uint256(_amount2),
                block.timestamp - weekStartTs(block.timestamp)
            )
        );

        assertFalse(ivotesAdapter.tokenIsDelegated(tokenId1));
        assertTrue(ivotesAdapter.tokenIsDelegated(tokenId2));

        assertEq(ivotesAdapter.numberOfDelegatedTokens(alice), 1);
        vm.stopPrank();
    }

    function _approve(uint160 _amount1, uint160 _amount2) private {
        vm.assume(_amount1 != 0 && _amount2 != 0);
        uint256 total = uint256(_amount1) + uint256(_amount2);
        token.transfer(alice, total);

        vm.prank(alice);
        token.approve(address(escrow), total);
    }
}
