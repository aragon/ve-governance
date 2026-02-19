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

contract TestSplit_ApproveDelegateAndSplit is
    IEscrowCurveTokenStorage,
    IEscrowCurveGlobalStorage,
    EscrowBase
{
    address alice = address(0x123);
    address bob = address(0x456);
    address charlie = address(0x789);

    uint256 aliceAmount = 30e18;
    uint256 checkpointTs;

    function setUp() public override {
        super.setUp();
        super.mintAndApproveEscrow();

        vm.warp(1);
        token.transfer(alice, aliceAmount);
        vm.warp(2 weeks + 1 hours + 1);
        escrow.enableSplit();

        // Alice creates a lock and delegates to Bob
        vm.startPrank(alice);
        {
            token.approve(address(escrow), aliceAmount);
            escrow.createLock(aliceAmount);
            ivotesAdapter.delegate(bob);
        }
        vm.stopPrank();

        checkpointTs = weekStartTs(block.timestamp);
    }

    function _approveCharlieAndSplit(uint256 _tokenId, uint256 _splitAmount) internal {
        vm.prank(alice);
        nftLock.approve(charlie, _tokenId);

        vm.prank(charlie);
        escrow.split(_tokenId, _splitAmount);
    }

    function _assertDelegatedToBob(uint256[] memory _tokenIds) internal view {
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            assertEq(ivotesAdapter.tokenIsDelegated(_tokenIds[i]), true);
        }
        assertEq(ivotesAdapter.numberOfDelegatedTokens(alice), _tokenIds.length);
        assertEq(ivotesAdapter.getVotes(bob), bias(aliceAmount, block.timestamp - checkpointTs));
        assertEq(ivotesAdapter.getVotes(alice), 0);
    }

    function _undelegateAndAssert(uint256[] memory _tokenIds) internal {
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

    /// @notice Alice creates a lock, delegates to Bob, approves Charlie,
    ///         then Charlie splits Alice's veNFT.
    ///         Both resulting tokens must remain delegated to Bob.
    ///         Alice then undelegates successfully.
    function test_Split_ByApprovedThirdParty_MaintainsDelegation() public {
        _approveCharlieAndSplit(1, 5e18);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;

        _assertDelegatedToBob(tokenIds);
        _undelegateAndAssert(tokenIds);
    }

    /// @notice Same as above but Bob votes on a gauge after receiving delegation.
    ///         The recorded vote on the gauge must remain unchanged after split.
    ///         Alice then undelegates successfully.
    function test_Split_ByApprovedThirdParty_MaintainsDelegationAndVotes() public {
        address gauge = address(0x777);
        voter.createGauge(gauge, "metadata");

        // Bob votes on the gauge (he has the delegated voting power)
        vm.prank(bob);
        voter.vote(_singleVote(gauge));

        assertEq(voter.votes(bob, gauge), bias(aliceAmount, block.timestamp - checkpointTs));

        _approveCharlieAndSplit(1, 5e18);

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;

        _assertDelegatedToBob(tokenIds);

        // Bob's gauge vote unchanged (split doesn't change total amount)
        assertEq(voter.votes(bob, gauge), bias(aliceAmount, block.timestamp - checkpointTs));

        _undelegateAndAssert(tokenIds);
    }

    /// @notice Charlie splits Alice's delegated veNFT multiple times.
    ///         All resulting tokens must remain delegated to Bob.
    ///         Alice then undelegates successfully.
    function test_Split_ByApprovedThirdParty_MultipleSplits_MaintainsDelegation() public {
        // Charlie splits: tokenId 1 (30e18) -> tokenId 1 (20e18) + tokenId 2 (10e18)
        _approveCharlieAndSplit(1, 10e18);

        // Charlie splits again: tokenId 1 (20e18) -> tokenId 1 (10e18) + tokenId 3 (10e18)
        _approveCharlieAndSplit(1, 10e18);

        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        tokenIds[2] = 3;

        _assertDelegatedToBob(tokenIds);
        _undelegateAndAssert(tokenIds);
    }

    function _singleVote(address _gauge) internal pure returns (IAddressGaugeVote.GaugeVote[] memory votes) {
        votes = new IAddressGaugeVote.GaugeVote[](1);
        votes[0] = IAddressGaugeVote.GaugeVote(100, _gauge);
    }
}
