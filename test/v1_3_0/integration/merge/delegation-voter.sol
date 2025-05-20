pragma solidity ^0.8.17;

import {EscrowBase, IAddressGaugeVote} from "../../base/EscrowBase.sol";

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
    function setUp() public override {
        super.setUp();

        super.mintAndApproveEscrow();
    }

    function test_Merge_CorrectlyUpdatesDelegationAndVotes() public {
        vm.warp(1);

        address alice = address(0x123);

        uint256 amount1 = 15e18;
        uint256 amount2 = 20e18;

        token.transfer(alice, amount1 + amount2);

        address gauge = address(0x777);

        curve.setWarmupPeriod(0);

        // activate cp & warp to an active window
        vm.warp(2 weeks + 1 hours + 1);
        voter.createGauge(gauge, "metadata");

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
}
