pragma solidity ^0.8.17;

import {TestMerge_ApproveDelegateBase} from "./delegate-approve-base.sol";

contract TestMerge_ApproveDelegateAndTransfer is TestMerge_ApproveDelegateBase {
    address dave = address(0xABC);
    address eve = address(0xDEF);

    function setUp() public override {
        super.setUp();
        nftLock.setWhitelisted(dave, true);

        // Dave sets Eve as his delegatee before receiving any tokens
        vm.prank(dave);
        ivotesAdapter.setDelegateAddress(eve);
    }

    function _removeDelegationAndAssert(uint256 _survivingTokenId) internal override {
        // Capture Bob's VP before transfer — Eve should receive the same amount
        uint256 expectedVP = ivotesAdapter.getVotes(bob);

        // Alice transfers the surviving token to whitelisted Dave (who already has Eve as delegatee)
        vm.prank(alice);
        nftLock.transferFrom(alice, dave, _survivingTokenId);

        // Transfer auto-delegates to Dave's pre-set delegatee Eve
        assertEq(ivotesAdapter.tokenIsDelegated(_survivingTokenId), true);
        assertEq(nftLock.ownerOf(_survivingTokenId), dave);
        assertEq(ivotesAdapter.numberOfDelegatedTokens(alice), 0);
        assertEq(ivotesAdapter.numberOfDelegatedTokens(dave), 1);
        // Eve now holds the voting power that Bob previously had
        assertEq(ivotesAdapter.getVotes(eve), expectedVP);
        assertEq(ivotesAdapter.getVotes(bob), 0);
        assertEq(ivotesAdapter.getVotes(dave), 0);
        assertEq(ivotesAdapter.getVotes(alice), 0);
    }

    /// @notice Alice has 3 tokens all delegated to Bob. Charlie merges token 1 into token 2.
    ///         Alice transfers only the merged token to Dave.
    ///         Bob retains voting power from token 3.
    function test_Merge_PartialTransfer_BobRetainsRemainingPower() public {
        uint256 amount3 = 10e18;
        token.transfer(alice, amount3);
        vm.startPrank(alice);
        token.approve(address(escrow), amount3);
        escrow.createLock(amount3); // tokenId 3
        ivotesAdapter.delegate(bob);
        vm.stopPrank();

        // Same start time — merge allowed without maturation
        _approveCharlieAndMerge(1, 2);

        vm.prank(alice);
        nftLock.transferFrom(alice, dave, 2);

        uint256 elapsed = block.timestamp - checkpointTs;
        assertEq(ivotesAdapter.numberOfDelegatedTokens(alice), 1);
        assertEq(ivotesAdapter.numberOfDelegatedTokens(dave), 1);
        assertEq(ivotesAdapter.getVotes(bob), bias(amount3, elapsed));
        assertEq(ivotesAdapter.getVotes(eve), bias(totalAmount, elapsed));
    }

    /// @notice Same as above but Bob votes on a gauge first.
    ///         After merge + partial transfer, Bob's gauge vote auto-decreases.
    function test_Merge_PartialTransfer_BobGaugeVoteDecreases() public {
        uint256 amount3 = 10e18;
        token.transfer(alice, amount3);
        vm.startPrank(alice);
        token.approve(address(escrow), amount3);
        escrow.createLock(amount3);
        ivotesAdapter.delegate(bob);
        vm.stopPrank();

        address gauge = address(0x777);
        voter.createGauge(gauge, "metadata");

        vm.prank(bob);
        voter.vote(_singleVote(gauge));

        uint256 elapsed = block.timestamp - checkpointTs;
        assertEq(voter.votes(bob, gauge), bias(totalAmount + amount3, elapsed));

        _approveCharlieAndMerge(1, 2);

        vm.prank(alice);
        nftLock.transferFrom(alice, dave, 2);

        // Bob's gauge vote auto-decreases without revoting
        assertEq(voter.votes(bob, gauge), bias(amount3, elapsed));
        assertEq(ivotesAdapter.getVotes(bob), bias(amount3, elapsed));
        assertEq(ivotesAdapter.getVotes(eve), bias(totalAmount, elapsed));
    }
}
