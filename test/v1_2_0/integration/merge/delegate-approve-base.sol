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

abstract contract TestMerge_ApproveDelegateBase is
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

    function setUp() public virtual override {
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

    function _removeDelegationAndAssert(uint256 _survivingTokenId) internal virtual;

    function _singleVote(address _gauge) internal pure returns (IAddressGaugeVote.GaugeVote[] memory votes) {
        votes = new IAddressGaugeVote.GaugeVote[](1);
        votes[0] = IAddressGaugeVote.GaugeVote(100, _gauge);
    }

    /// @notice Alice has token 1 undelegated and token 2 delegated to Bob.
    ///         Charlie (approved) merges token 1 into token 2.
    ///         The surviving token 2 must remain delegated to Bob with combined voting power.
    ///         Alice then removes delegation successfully.
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

        _removeDelegationAndAssert(2);
    }

    /// @notice Alice has token 1 undelegated and token 2 delegated to Bob.
    ///         Bob votes on a gauge with his delegated power.
    ///         Charlie (approved) merges token 1 into token 2.
    ///         The surviving token 2 must remain delegated to Bob with combined voting power.
    ///         Bob's gauge vote must remain unchanged after merge.
    ///         Alice then removes delegation successfully.
    function test_Merge_UndelegatedInto_Delegated_ByApprovedThirdParty_WithVote() public {
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

        // Bob votes on a gauge with his delegated voting power
        address gauge = address(0x777);
        voter.createGauge(gauge, "metadata");

        vm.prank(bob);
        voter.vote(_singleVote(gauge));

        uint256 bobVoteAtGauge = voter.votes(bob, gauge);
        assertEq(bobVoteAtGauge, ivotesAdapter.getVotes(bob));

        // Both locks have the same start time, so merge is allowed without maturation
        _approveCharlieAndMerge(1, 2);

        // Token 1 is burned, token 2 survives and remains delegated
        assertEq(ivotesAdapter.tokenIsDelegated(2), true);
        assertEq(ivotesAdapter.numberOfDelegatedTokens(alice), 1);
        // Bob's voting power should reflect the combined amount
        assertEq(ivotesAdapter.getVotes(bob), bias(totalAmount, block.timestamp - checkpointTs));

        // Bob's gauge vote unchanged from when he voted (pre-merge, only amount2 delegated)
        assertEq(voter.votes(bob, gauge), bobVoteAtGauge);

        // Bob revotes to use his increased voting power from the merge
        vm.prank(bob);
        voter.vote(_singleVote(gauge));

        // Bob's gauge vote now reflects the combined amount
        assertEq(voter.votes(bob, gauge), bias(totalAmount, block.timestamp - checkpointTs));

        _removeDelegationAndAssert(2);
    }

    /// @notice Alice has token 1 delegated to Bob and token 2 undelegated.
    ///         Charlie (approved) merges token 1 into token 2.
    ///         The surviving token 2 must become delegated to Bob with combined voting power.
    ///         Alice then removes delegation successfully.
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

        _removeDelegationAndAssert(2);
    }

    /// @notice Both of Alice's tokens are delegated to Bob.
    ///         Charlie (approved) merges token 1 into token 2.
    ///         The surviving token 2 must remain delegated to Bob with combined voting power.
    ///         Alice then removes delegation successfully.
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

        _removeDelegationAndAssert(2);
    }
}
