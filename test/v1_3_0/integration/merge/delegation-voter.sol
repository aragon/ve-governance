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
        address bob = address(0x456);

        uint256 aliceAmount = 15e18;
        uint256 bobAmount = 20e18;

        token.transfer(alice, aliceAmount);
        token.transfer(bob, bobAmount);

        address gauge = address(0x777);

        curve.setWarmupPeriod(0);

        // activate cp & warp to an active window
        vm.warp(2 weeks + 1 hours + 1);
        voter.createGauge(gauge, "metadata");

        // alice creates lock, delegates to herself and votes.
        {
            vm.startPrank(alice);
            token.approve(address(escrow), aliceAmount);
            escrow.createLock(aliceAmount);
            ivotesAdapter.delegate(alice);
            nftLock.setApprovalForAll(address(this), true);

            IAddressGaugeVote.GaugeVote[] memory votes = new IAddressGaugeVote.GaugeVote[](1);
            votes[0] = IAddressGaugeVote.GaugeVote(100, gauge);
            voter.vote(votes);

            vm.stopPrank();
        }

        // bob creates lock, delegates to himself and votes.
        {
            vm.startPrank(bob);
            token.approve(address(escrow), bobAmount);
            escrow.createLock(bobAmount);
            ivotesAdapter.delegate(bob);
            nftLock.setApprovalForAll(address(this), true);

            IAddressGaugeVote.GaugeVote[] memory votes = new IAddressGaugeVote.GaugeVote[](1);
            votes[0] = IAddressGaugeVote.GaugeVote(100, gauge);
            voter.vote(votes);
            vm.stopPrank();
        }

        uint256 checkpointTs = weekStartTs(block.timestamp);

        // Assert pre-state before running merge.
        uint256 aliceBias = bias(aliceAmount, block.timestamp - checkpointTs);
        uint256 bobBias = bias(bobAmount, block.timestamp - checkpointTs);

        assertEq(voter.votes(alice, gauge), aliceBias);
        assertEq(voter.votes(bob, gauge), bobBias);
        assertEq(ivotesAdapter.getVotes(alice), aliceBias);
        assertEq(ivotesAdapter.getVotes(bob), bobBias);
        assertTrue(ivotesAdapter.tokenIsDelegated(1));
        assertTrue(ivotesAdapter.tokenIsDelegated(2));

        // Run merge
        uint256 lockEnd = checkpointTs + maxTime;
        vm.warp(lockEnd + 1 seconds);
        escrow.merge(1, 2);

        // Assert state after merge..

        // Since tokenId = 1 is burnt due to merge,
        // Alice must lose its power on the delegation.
        assertEq(ivotesAdapter.getVotes(alice), 0);

        // Since tokenId 1 is merged into tokenId2 and
        // Bob already had a delegate(himself),his delegation
        // power must increase by tokenId 1's power.
        assertEq(ivotesAdapter.getVotes(bob), bias(35e18, lockEnd - checkpointTs));

        // Gauge must lose Alice's recorded vote as token got burnt.
        assertEq(voter.votes(alice, gauge), 0);

        // Note that bob's recorded votes must not increase as
        // we do not update vote record on an increasing voting power.
        // See AddressGaugeVoter for more details.
        assertEq(voter.votes(bob, gauge), bobBias);

        // assertFalse(ivotesAdapter.tokenIsDelegated(1));
        assertTrue(ivotesAdapter.tokenIsDelegated(2));
    }
}
