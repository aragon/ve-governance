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
    IEscrowCurveGlobalStorage,
    EscrowIVotesAdapter,
    IEscrowIVotesAdapterErrorsAndEvents
} from "../../versions.sol";

import {ReentrancyDelegate} from "../utils/ReentrancyDelegate.sol";

contract TestCreateLock_DelegationAndVoter is
    IEscrowCurveTokenStorage,
    IEscrowCurveGlobalStorage,
    EscrowBase
{
    function setUp() public override {
        super.setUp();

        super.mintAndApproveEscrow();
    }

    function test_CreateLock_CorrectlyUpdatesDelegationAndVotes() public {
        vm.warp(1);

        address alice = address(0x123);
        uint256 lock1Amount = 15e18;
        uint256 lock2Amount = 35e18;

        token.transfer(alice, lock1Amount + lock2Amount);

        address gauge = address(0x777);

        // activate cp & warp to an active window
        vm.warp(2 weeks + 1 hours + 1);
        voter.createGauge(gauge, "metadata");

        // alice creates lock, delegates to herself and votes.
        {
            vm.startPrank(alice);
            ivotesAdapter.delegate(alice);

            token.approve(address(escrow), lock1Amount);
            escrow.createLock(lock1Amount);

            IAddressGaugeVote.GaugeVote[] memory votes = new IAddressGaugeVote.GaugeVote[](1);
            votes[0] = IAddressGaugeVote.GaugeVote(100, gauge);
            voter.vote(votes);
            vm.stopPrank();
        }

        uint256 checkpointTs = weekStartTs(block.timestamp);

        uint256 alice1Bias = bias(lock1Amount, block.timestamp - checkpointTs);
        uint256 alice2Bias = bias(lock2Amount, block.timestamp - checkpointTs);
        assertEq(ivotesAdapter.getVotes(alice), alice1Bias);
        assertEq(voter.votes(alice, gauge), alice1Bias);
        assertTrue(ivotesAdapter.tokenIsDelegated(1));
        assertEq(ivotesAdapter.numberOfDelegatedTokens(alice), 1);

        // alice creates second lock which should
        // automatically increase her delegation power.
        {
            vm.startPrank(alice);
            token.approve(address(escrow), lock2Amount);
            escrow.createLock(lock2Amount);
            vm.stopPrank();
        }

        assertEq(ivotesAdapter.getVotes(alice), alice1Bias + alice2Bias);
        assertEq(voter.votes(alice, gauge), alice1Bias);
        assertTrue(ivotesAdapter.tokenIsDelegated(2));
        assertEq(ivotesAdapter.numberOfDelegatedTokens(alice), 2);
    }

    // Ensures that even if `.mint` call on the new tokenId
    // calls back `delegate([tokenIds])` by ERC721Received function,
    // It will revert. Otherwise, it would cause voting power on Alice
    // to double on escrowIVotesAdapter.
    function testRevert_Reentrancy_IfDelegateTokenIsCalledFromTokenMint() public {
        escrow.enableSplit();

        address delegatee = address(new ReentrancyDelegate(address(escrow), address(ivotesAdapter)));
        token.mint(delegatee, 10e18);

        //  contract delegatee delegates to Alice
        address alice = address(123);
        vm.prank(delegatee);
        ivotesAdapter.setDelegateAddress(alice);

        uint256 expectedTokenId = 1;

        {
            uint256[] memory ids = new uint256[](1);
            ids[0] = expectedTokenId;
            ReentrancyDelegate(delegatee).setParams(abi.encodeWithSignature("delegate(uint256[])", ids));
            ReentrancyDelegate(delegatee).enableExploit(true);
        }

        // createLock calls token.mint which calls `delegate([newTokenId])` on escrowAdapter.
        // This must revert as before `token.mint` is called, `_moveDelegateVotes` already
        // makes this new token as "delegated: true`.
        vm.expectRevert(
            abi.encodeWithSelector(
                IEscrowIVotesAdapterErrorsAndEvents.TokenAlreadyDelegated.selector,
                expectedTokenId
            )
        );
        escrow.createLockFor(10e18, delegatee);
    }
}
