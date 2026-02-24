pragma solidity ^0.8.17;

import {TestSplit_ApproveDelegateBase} from "./delegate-approve-base.sol";

contract TestSplit_ApproveDelegateAndSplit is TestSplit_ApproveDelegateBase {
    function _removeDelegationAndAssert(uint256[] memory _tokenIds) internal override {
        vm.prank(alice);
        ivotesAdapter.undelegate(_tokenIds);

        for (uint256 i = 0; i < _tokenIds.length; i++) {
            assertEq(ivotesAdapter.tokenIsDelegated(_tokenIds[i]), false);
        }
        assertEq(ivotesAdapter.numberOfDelegatedTokens(alice), 0);
        // Bob loses delegated voting power, Alice has none either (tokens are undelegated, not self-delegated)
        assertEq(ivotesAdapter.getVotes(bob), 0);
        assertEq(ivotesAdapter.getVotes(alice), 0);
    }
}
