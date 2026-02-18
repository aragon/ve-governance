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

contract TestMerge_ApproveDelegateAndMerge is
    IEscrowCurveTokenStorage,
    IEscrowCurveGlobalStorage,
    EscrowBase
{
    address alice = address(0x123);
    address bob = address(0x456);
    address charlie = address(0x789);

    uint256 amount1 = 15e18;
    uint256 amount2 = 20e18;
    uint256 totalAmount;

    uint256 checkpointTs;
    uint256 writtenTs;

    function setUp() public override {
        super.setUp();
        super.mintAndApproveEscrow();

        totalAmount = amount1 + amount2;

        vm.warp(1);
        token.transfer(alice, totalAmount);
        vm.warp(2 weeks + 1 hours + 1);

        // Alice creates 2 locks in the same block (same start time for merge compatibility)
        vm.startPrank(alice);
        {
            token.approve(address(escrow), totalAmount);
            escrow.createLock(amount1); // tokenId 1
            escrow.createLock(amount2); // tokenId 2
        }
        vm.stopPrank();

        checkpointTs = weekStartTs(block.timestamp);
        writtenTs = block.timestamp;
    }

    function _warpPastMaturation() internal {
        uint256 lockEnd = getEndTimestamp(checkpointTs, writtenTs);
        vm.warp(lockEnd + 1 seconds);
    }

    function _approveCharlieAndMerge(uint256 _from, uint256 _to) internal {
        vm.prank(alice);
        nftLock.setApprovalForAll(charlie, true);

        vm.prank(charlie);
        escrow.merge(_from, _to);
    }

    function _undelegateAndAssert(uint256 _survivingTokenId) internal {
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = _survivingTokenId;

        vm.prank(alice);
        ivotesAdapter.undelegate(tokenIds);

        assertEq(ivotesAdapter.tokenIsDelegated(_survivingTokenId), false);
        assertEq(ivotesAdapter.numberOfDelegatedTokens(alice), 0);
        assertEq(ivotesAdapter.getVotes(bob), 0);
        assertEq(ivotesAdapter.getVotes(alice), 0);
    }

    /// @notice Alice has token 1 undelegated and token 2 delegated to Bob.
    ///         Charlie (approved) merges token 1 into token 2.
    ///         The surviving token 2 must remain delegated to Bob with combined voting power.
    ///         Alice then undelegates successfully.
    function test_Merge_UndelegatedInto_Delegated_ByApprovedThirdParty() public {
        // Alice sets Bob as delegatee and only delegates token 2
        uint256[] memory delegateIds = new uint256[](1);
        delegateIds[0] = 2;
        vm.startPrank(alice);
        ivotesAdapter.setDelegateAddress(bob);
        ivotesAdapter.delegate(delegateIds);
        vm.stopPrank();

        assertEq(ivotesAdapter.tokenIsDelegated(1), false);
        assertEq(ivotesAdapter.tokenIsDelegated(2), true);
        assertEq(ivotesAdapter.numberOfDelegatedTokens(alice), 1);

        // Warp past maturation so locks can merge (different effective amounts but same start)
        _warpPastMaturation();

        // Charlie merges token 1 (undelegated) into token 2 (delegated)
        _approveCharlieAndMerge(1, 2);

        // Token 1 is burned, token 2 survives and remains delegated
        assertEq(ivotesAdapter.tokenIsDelegated(2), true);
        assertEq(ivotesAdapter.numberOfDelegatedTokens(alice), 1);
        // Bob's voting power should reflect the combined amount
        assertEq(ivotesAdapter.getVotes(bob), bias(totalAmount, maxTime));

        _undelegateAndAssert(2);
    }

    /// @notice Alice has token 1 delegated to Bob and token 2 undelegated.
    ///         Charlie (approved) merges token 1 into token 2.
    ///         The surviving token 2 must become delegated to Bob with combined voting power.
    ///         Alice then undelegates successfully.
    function test_Merge_DelegatedInto_Undelegated_ByApprovedThirdParty() public {
        // Alice sets Bob as delegatee and only delegates token 1
        uint256[] memory delegateIds = new uint256[](1);
        delegateIds[0] = 1;
        vm.startPrank(alice);
        ivotesAdapter.setDelegateAddress(bob);
        ivotesAdapter.delegate(delegateIds);
        vm.stopPrank();

        assertEq(ivotesAdapter.tokenIsDelegated(1), true);
        assertEq(ivotesAdapter.tokenIsDelegated(2), false);
        assertEq(ivotesAdapter.numberOfDelegatedTokens(alice), 1);

        _warpPastMaturation();

        // Charlie merges token 1 (delegated) into token 2 (undelegated)
        _approveCharlieAndMerge(1, 2);

        // Token 1 is burned, token 2 survives and should become delegated
        // (mergeDelegateVotes: from=delegated, to=undelegated -> to becomes delegated)
        assertEq(ivotesAdapter.tokenIsDelegated(2), true);
        assertEq(ivotesAdapter.numberOfDelegatedTokens(alice), 1);
        assertEq(ivotesAdapter.getVotes(bob), bias(totalAmount, maxTime));

        _undelegateAndAssert(2);
    }

    /// @notice Both of Alice's tokens are delegated to Bob.
    ///         Charlie (approved) merges token 1 into token 2.
    ///         The surviving token 2 must remain delegated to Bob with combined voting power.
    ///         Alice then undelegates successfully.
    function test_Merge_BothDelegated_ByApprovedThirdParty() public {
        // Alice delegates to Bob (both tokens get delegated)
        vm.prank(alice);
        ivotesAdapter.delegate(bob);

        assertEq(ivotesAdapter.tokenIsDelegated(1), true);
        assertEq(ivotesAdapter.tokenIsDelegated(2), true);
        assertEq(ivotesAdapter.numberOfDelegatedTokens(alice), 2);

        _warpPastMaturation();

        // Charlie merges token 1 into token 2 (both delegated)
        _approveCharlieAndMerge(1, 2);

        // Token 1 is burned, token 2 survives and remains delegated
        assertEq(ivotesAdapter.tokenIsDelegated(1), false);
        assertEq(ivotesAdapter.tokenIsDelegated(2), true);
        assertEq(ivotesAdapter.numberOfDelegatedTokens(alice), 1);
        assertEq(ivotesAdapter.getVotes(bob), bias(totalAmount, maxTime));

        _undelegateAndAssert(2);
    }
}
