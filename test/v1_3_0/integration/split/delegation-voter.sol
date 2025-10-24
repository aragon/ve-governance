pragma solidity ^0.8.17;

import {EscrowBase, IAddressGaugeVote} from "../../base/EscrowBase.sol";
import {console2 as console} from "forge-std/console2.sol";
import {Vm} from "forge-std/Vm.sol";

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
    IEscrowIVotesAdapterErrorsAndEvents,
    IGaugeVote
} from "../../versions.sol";

import {ReentrancyDelegate} from "../utils/ReentrancyDelegate.sol";

contract TestSplit_DelegationAndVoter is
    IEscrowCurveTokenStorage,
    IEscrowCurveGlobalStorage,
    EscrowBase
{
    address gauge = address(0x777);
    address alice = address(0x123);
    address bob = address(0x192);

    function setUp() public override {
        super.setUp();

        vm.warp(2 weeks + 1 hours + 1);
        voter.createGauge(gauge, "metadata");
        escrow.enableSplit();
    }

    function test_Split_CorrectlyUpdatesDelegationAndVotes() public {
        super.mintAndApproveEscrow();

        uint256 aliceAmount = 30e18;
        token.transfer(alice, aliceAmount);

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
    function testRevert_Reentrancy_IfDelegateTokenIsCalledFromTokenMint() public {
        super.mintAndApproveEscrow();

        escrow.enableSplit();

        address delegatee = address(new ReentrancyDelegate(address(escrow), address(ivotesAdapter)));
        token.mint(delegatee, 10e18);

        // C delegates to Alice
        vm.prank(delegatee);
        ivotesAdapter.setDelegateAddress(alice);

        // tokenId gets created by `delegatee` address.
        // This should automatically assign voting power
        // of this tokenId to alice, because `delegatee` set its own
        // delegate as Alice.
        uint256 tokenId = escrow.createLockFor(10e18, delegatee);
        uint256 splitTokenId = tokenId + 1;

        {
            uint256[] memory ids = new uint256[](1);
            ids[0] = splitTokenId;
            ReentrancyDelegate(delegatee).setParams(abi.encodeWithSignature("delegate(uint256[])", ids));
            ReentrancyDelegate(delegatee).enableExploit(true);
        }

        // Split calls token.mint which calls `delegate([newTokenId])` on escrowAdapter.
        // This must revert as before `token.mint` is called, `_moveDelegateVotes` already
        // makes this new token as "delegated: true`.
        vm.prank(delegatee);
        vm.expectRevert(
            abi.encodeWithSelector(
                IEscrowIVotesAdapterErrorsAndEvents.TokenAlreadyDelegated.selector,
                splitTokenId
            )
        );
        escrow.split(tokenId, 3e18);
    }

    function test_Reentrancy_IfDelegateAddressIsCalledFromTokenMint() public {
        super.mintAndApproveEscrow();

        escrow.enableSplit();

        address delegatee = address(new ReentrancyDelegate(address(escrow), address(ivotesAdapter)));
        token.mint(delegatee, 10e18);

        // C delegates to Alice
        vm.prank(delegatee);
        ivotesAdapter.setDelegateAddress(alice);

        // tokenId gets created by `delegatee` address.
        // This should automatically assign voting power
        // of this tokenId to alice, because `delegatee` set its own
        // delegate as Alice.
        uint256 tokenId = escrow.createLockFor(10e18, delegatee);

        {
            ReentrancyDelegate(delegatee).setParams(abi.encodeWithSignature("delegate(address)", alice));
            ReentrancyDelegate(delegatee).enableExploit(true);
        }

        uint256 vpBefore = ivotesAdapter.getVotes(alice);

        // Split calls token.mint which calls `delegate(address)` on escrowAdapter.
        // This must not cause any change in `getVotes` because `delegate(address)`
        // undelegates all tokens that were delegated and delegates them. In this
        // test case, delegatee address doesn't change and is Alice.
        vm.prank(delegatee);
        escrow.split(tokenId, 3e18);

        uint256 vpAfter = ivotesAdapter.getVotes(alice);

        assertEq(vpBefore, vpAfter);
    }
    
    function testFuzz_Split_WhenTokenIsNotDelegated(uint192 _amount, uint192 _splitAmount, uint192 _minDeposit) public {
        super.mintAndApproveEscrow(type(uint256).max);

        vm.assume(_minDeposit != 0);
        vm.assume(_amount > _splitAmount);
        vm.assume(_splitAmount > _minDeposit);
        vm.assume(_amount - _splitAmount > _minDeposit);

        escrow.setMinDeposit(_minDeposit);
        _approve(alice, _amount);

        vm.startPrank(alice);
        uint256 tokenId1 = escrow.createLock(_amount);

        assertFalse(ivotesAdapter.tokenIsDelegated(tokenId1));

        vm.recordLogs();
        escrow.split(tokenId1, _splitAmount);
        _ensureNotEmitted(TokensDelegatedSignature);
        _ensureNotEmitted(TokensUndelegatedSignature);

        assertEq(ivotesAdapter.getPastVotes(bob, block.timestamp), 0);

        assertFalse(ivotesAdapter.tokenIsDelegated(tokenId1));
        assertFalse(ivotesAdapter.tokenIsDelegated(tokenId1 + 1));
        assertEq(ivotesAdapter.numberOfDelegatedTokens(alice), 0);
        vm.stopPrank();
    }

    function testFuzz_Split_WhenTokenIsDelegated(uint192 _amount, uint192 _splitAmount, uint192 _minDeposit) public {
        super.mintAndApproveEscrow(type(uint256).max);

        vm.assume(_minDeposit != 0);
        vm.assume(_amount > _splitAmount);
        vm.assume(_splitAmount > _minDeposit);
        vm.assume(_amount - _splitAmount > _minDeposit);

        escrow.setMinDeposit(_minDeposit);
        _approve(alice, _amount);

        vm.startPrank(alice);
        ivotesAdapter.setDelegateAddress(bob);
        uint256 tokenId1 = escrow.createLock(_amount);

        assertTrue(ivotesAdapter.tokenIsDelegated(tokenId1));

        vm.expectEmit();
        emit TokensDelegated(alice, bob, _getTokenIdList(tokenId1 + 1));
        vm.recordLogs();
        escrow.split(tokenId1, _splitAmount);
        _ensureNotEmitted(TokensUndelegatedSignature);

        assertEq(
            ivotesAdapter.getPastVotes(bob, block.timestamp),
            bias(_amount, block.timestamp - weekStartTs(block.timestamp))
        );

        assertTrue(ivotesAdapter.tokenIsDelegated(tokenId1));
        assertTrue(ivotesAdapter.tokenIsDelegated(tokenId1 + 1));
        assertEq(ivotesAdapter.numberOfDelegatedTokens(alice), 2);
        vm.stopPrank();
    }

    function _approve(address _who, uint256 _amount) private {
        token.transfer(_who, _amount);

        vm.prank(_who);
        token.approve(address(escrow), _amount);
    }
}
