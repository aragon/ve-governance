pragma solidity ^0.8.17;

import {TestSplit_ApproveDelegateBase} from "./delegate-approve-base.sol";

contract TestSplit_ApproveDelegateAndTransfer is TestSplit_ApproveDelegateBase {
    address dave = address(0xABC);
    address eve = address(0xDEF);

    function setUp() public override {
        super.setUp();
        nftLock.setWhitelisted(dave, true);

        // Dave sets Eve as his delegatee before receiving any tokens
        vm.prank(dave);
        ivotesAdapter.setDelegateAddress(eve);
    }

    function _removeDelegationAndAssert(uint256[] memory _tokenIds) internal override {
        // Alice transfers all tokens to whitelisted Dave (who already has Eve as delegatee)
        vm.startPrank(alice);
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            nftLock.transferFrom(alice, dave, _tokenIds[i]);
        }
        vm.stopPrank();

        // Transfer auto-delegates to Dave's pre-set delegatee Eve
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            assertEq(ivotesAdapter.tokenIsDelegated(_tokenIds[i]), true);
            assertEq(nftLock.ownerOf(_tokenIds[i]), dave);
        }
        assertEq(ivotesAdapter.numberOfDelegatedTokens(alice), 0);
        assertEq(ivotesAdapter.numberOfDelegatedTokens(dave), _tokenIds.length);
        // Eve now holds the voting power that Bob previously had
        assertEq(ivotesAdapter.getVotes(eve), bias(aliceAmount, block.timestamp - checkpointTs));
        assertEq(ivotesAdapter.getVotes(bob), 0);
        assertEq(ivotesAdapter.getVotes(dave), 0);
        assertEq(ivotesAdapter.getVotes(alice), 0);
    }

    /// @notice After split, Alice transfers only the split-off token to Dave.
    ///         Bob retains voting power from the remaining token.
    function test_Split_PartialTransfer_BobRetainsRemainingPower() public {
        uint256 splitAmount = 5e18;
        _approveCharlieAndSplit(1, splitAmount);

        vm.prank(alice);
        nftLock.transferFrom(alice, dave, 2);

        uint256 elapsed = block.timestamp - checkpointTs;
        assertEq(ivotesAdapter.numberOfDelegatedTokens(alice), 1);
        assertEq(ivotesAdapter.numberOfDelegatedTokens(dave), 1);
        assertEq(ivotesAdapter.getVotes(bob), bias(aliceAmount - splitAmount, elapsed));
        assertEq(ivotesAdapter.getVotes(eve), bias(splitAmount, elapsed));
    }

    /// @notice After split + partial transfer, Bob's gauge vote decreases automatically
    ///         to reflect only the remaining token's voting power.
    function test_Split_PartialTransfer_BobGaugeVoteDecreases() public {
        uint256 splitAmount = 5e18;

        address gauge = address(0x777);
        voter.createGauge(gauge, "metadata");

        vm.prank(bob);
        voter.vote(_singleVote(gauge));

        uint256 elapsed = block.timestamp - checkpointTs;
        assertEq(voter.votes(bob, gauge), bias(aliceAmount, elapsed));

        _approveCharlieAndSplit(1, splitAmount);

        vm.prank(alice);
        nftLock.transferFrom(alice, dave, 2);

        // Bob's gauge vote auto-decreases without revoting
        assertEq(voter.votes(bob, gauge), bias(aliceAmount - splitAmount, elapsed));
        assertEq(ivotesAdapter.getVotes(bob), bias(aliceAmount - splitAmount, elapsed));
        assertEq(ivotesAdapter.getVotes(eve), bias(splitAmount, elapsed));
    }
}
