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

contract TestSplit_DelegationAndVoter is
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

    function test_Split_CorrectlyUpdatesDelegationAndVotes() public {
        uint256 aliceAmount = 30e18;
        token.transfer(alice, aliceAmount);

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

        // // Even though tokenId was destroyed, split produced
        // // 2 new tokenIds of which's power sum must be the same.
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

    function testFuzz_Split_WhenTokenIsNotDelegated(uint192 _amount) public {
        uint256 minDeposit = 100;
        escrow.setMinDeposit(minDeposit);
        _approve(_amount, minDeposit);

        vm.startPrank(alice);
        uint256 tokenId1 = escrow.createLock(_amount);

        assertFalse(ivotesAdapter.tokenIsDelegated(tokenId1));

        escrow.split(tokenId1, minDeposit);
        assertEq(ivotesAdapter.getPastVotes(bob, block.timestamp), 0);

        assertFalse(ivotesAdapter.tokenIsDelegated(tokenId1));
        assertFalse(ivotesAdapter.tokenIsDelegated(tokenId1 + 1));
        assertEq(ivotesAdapter.numberOfDelegatedTokens(alice), 0);
        vm.stopPrank();
    }

    function testFuzz_Split_WhenTokenIsDelegated(uint192 _amount) public {
        uint256 minDeposit = 100;
        escrow.setMinDeposit(minDeposit);
        _approve(_amount, minDeposit);

        vm.startPrank(alice);
        ivotesAdapter.setDelegateAddress(bob);
        uint256 tokenId1 = escrow.createLock(_amount);

        assertTrue(ivotesAdapter.tokenIsDelegated(tokenId1));

        escrow.split(tokenId1, minDeposit);
        assertEq(
            ivotesAdapter.getPastVotes(bob, block.timestamp),
            bias(_amount, block.timestamp - weekStartTs(block.timestamp))
        );

        assertTrue(ivotesAdapter.tokenIsDelegated(tokenId1));
        assertTrue(ivotesAdapter.tokenIsDelegated(tokenId1 + 1));
        assertEq(ivotesAdapter.numberOfDelegatedTokens(alice), 2);
        vm.stopPrank();
    }

    function _approve(uint256 _amount, uint256 _minDeposit) private {
        vm.assume(_amount >= _minDeposit);
        token.transfer(alice, _amount);

        vm.prank(alice);
        token.approve(address(escrow), _amount);
    }

    function _approve(address _who, uint256 _amount) private {
        token.transfer(_who, _amount);

        vm.prank(_who);
        token.approve(address(escrow), _amount);
    }
}
