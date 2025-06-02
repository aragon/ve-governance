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

contract TestSplit_DelegationAndVoter is
    IEscrowCurveTokenStorage,
    IEscrowCurveGlobalStorage,
    EscrowBase
{
    function setUp() public override {
        super.setUp();

        super.mintAndApproveEscrow();
    }

    function test_Split_CorrectlyUpdatesDelegationAndVotes() public {
        vm.warp(1);

        address alice = address(0x123);
        uint256 aliceAmount = 30e18;
        token.transfer(alice, aliceAmount);

        vm.warp(2 weeks + 1 hours + 1);
        address gauge = address(0x777);
        voter.createGauge(gauge, "metadata");
        escrow.enableSplit();

        // turn on delegation to alice, so when she splits,
        // we can test that her delegation automatically updates.
        {
            vm.startPrank(alice);
            token.approve(address(escrow), aliceAmount);
            escrow.createLock(aliceAmount);
            ivotesAdapter.delegate(alice);

            IAddressGaugeVote.GaugeVote[] memory votes = new IAddressGaugeVote.GaugeVote[](1);
            votes[0] = IAddressGaugeVote.GaugeVote(100, gauge);
            voter.vote(votes);

            vm.stopPrank();
        }

        uint256 checkpointTs = weekStartTs(block.timestamp);

        assertEq(ivotesAdapter.tokenIsDelegated(1), true);
        assertEq(ivotesAdapter.numberOfDelegatedTokens(alice), 1);
        assertEq(voter.votes(alice, gauge), bias(aliceAmount, block.timestamp - checkpointTs));
        assertEq(ivotesAdapter.getVotes(alice), bias(aliceAmount, block.timestamp - checkpointTs));

        vm.prank(alice);
        escrow.split(1, 5e18);

        // Even though tokenId was destroyed, split produced
        // 2 new tokenIds of which's power sum must be the same.
        assertEq(ivotesAdapter.getVotes(alice), bias(aliceAmount, block.timestamp - checkpointTs));
        assertEq(ivotesAdapter.tokenIsDelegated(1), true);
        assertEq(ivotesAdapter.tokenIsDelegated(2), true);
        assertEq(ivotesAdapter.numberOfDelegatedTokens(alice), 2);

        // Even though `split` was called not by owner of the token, but address(this), it still
        // shouldn't change any behaviour. It's still alice that gets minted a new tokenId.
        // Note that split doesn't change the total amount for Alice, so her recorded voting power
        // should stay the same on voter.
        assertEq(voter.votes(alice, gauge), bias(aliceAmount, block.timestamp - checkpointTs));
    }
}
