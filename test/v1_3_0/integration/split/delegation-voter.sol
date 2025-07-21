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

    // Ensures that even if `.mint` call on the new tokenId
    // calls back `delegate([tokenIds])` by ERC721Received function,
    // It will revert. Otherwise, it would cause voting power on Alice
    // to increase more than original token's voting power even though
    // split must not cause any such anomaly.
    function testRevert_IfDelegateTokenIsCalledFromTokenMint() public {
        escrow.enableSplit();

        address c = address(new ReentrancyDelegate(address(escrow), address(ivotesAdapter)));
        token.mint(c, 10e18);

        // C delegates to Alice
        address alice = address(123);
        vm.prank(c);
        ivotesAdapter.setDelegateAddress(alice);

        // tokenId gets created by `c` address.
        // This should automatically assign voting power
        // of this tokenId to alice, because `c` set its own
        // delegate as Alice.
        uint256 tokenId = escrow.createLockFor(10e18, c);
        uint256 splitTokenId = tokenId + 1;

        {
            uint256[] memory ids = new uint256[](1);
            ids[0] = splitTokenId;
            ReentrancyDelegate(c).setParams(abi.encodeWithSignature("delegate(uint256[])", ids));
            ReentrancyDelegate(c).enableExploit(true);
        }

        // Split calls token.mint which calls `delegate([newTokenId])` on escrowAdapter.
        // This must revert as before `token.mint` is called, `_moveDelegateVotes` already
        // makes this new token as "delegated: true`.
        vm.prank(c);
        vm.expectRevert(
            abi.encodeWithSelector(
                IEscrowIVotesAdapterErrorsAndEvents.TokenAlreadyDelegated.selector,
                splitTokenId
            )
        );
        escrow.split(tokenId, 3e18);
    }

    function testRevert_IfDelegateAddressIsCalledFromTokenMint() public {
        escrow.enableSplit();

        address c = address(new ReentrancyDelegate(address(escrow), address(ivotesAdapter)));
        token.mint(c, 10e18);

        // C delegates to Alice
        address alice = address(123);
        vm.prank(c);
        ivotesAdapter.setDelegateAddress(alice);

        // tokenId gets created by `c` address.
        // This should automatically assign voting power
        // of this tokenId to alice, because `c` set its own
        // delegate as Alice.
        uint256 tokenId = escrow.createLockFor(10e18, c);
        uint256 splitTokenId = tokenId + 1;

        {
            ReentrancyDelegate(c).setParams(abi.encodeWithSignature("delegate(address)", alice));
            ReentrancyDelegate(c).enableExploit(true);
        }

        uint256 vpBefore = ivotesAdapter.getVotes(alice);

        // Split calls token.mint which calls `delegate([newTokenId])` on escrowAdapter.
        // This must revert as before `token.mint` is called, `_moveDelegateVotes` already
        // makes this new token as "delegated: true`.
        vm.prank(c);
        escrow.split(tokenId, 3e18);

        uint256 vpAfter = ivotesAdapter.getVotes(alice);

        assertEq(vpBefore, vpAfter);
    }
}
