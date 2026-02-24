pragma solidity ^0.8.17;

import {TestMerge_ApproveDelegateBase} from "./delegate-approve-base.sol";

contract TestMerge_ApproveDelegateAndMerge is TestMerge_ApproveDelegateBase {
    function _removeDelegationAndAssert(uint256 _survivingTokenId) internal override {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = _survivingTokenId;

        vm.prank(alice);
        ivotesAdapter.undelegate(tokenIds);

        assertEq(ivotesAdapter.tokenIsDelegated(_survivingTokenId), false);
        assertEq(ivotesAdapter.numberOfDelegatedTokens(alice), 0);
        assertEq(ivotesAdapter.getVotes(bob), 0);
        assertEq(ivotesAdapter.getVotes(alice), 0);
    }
}
