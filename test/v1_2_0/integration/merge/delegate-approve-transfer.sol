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
}
