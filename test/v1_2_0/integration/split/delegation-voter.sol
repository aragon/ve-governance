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
import {console2 as console} from "forge-std/console2.sol";

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

        // Even though tokenId was destroyed, split produced
        // 2 new tokenIds of which's power sum must be the same.
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

    // Scenario:
    // 1. Alice creates lock (i.e tokenId = 5)
    // 2. Alice calls `setDelegateAddress(Bob)`
    // 3. Alice calls split(5) which causes tokenId = 6 to be created. Since Alice already has bob as her delegator, inside `split`, following
    // is called. _moveDelegateVotes(address(0), owner, newTokenId, LockedBalance(0, 0)); This causes `tokenId = 6` to be set as delegated, but
    // since no balance in `LockedBalance` is set, delegatee(Bob) will still have 0 `getPastVotes`. 

    // The issue doesn't occur in a situation where tokenId = 5 was already delegated in a way that its vp was already applied in EscrowIVotesAdapter.

    // The solution of our code is: 
    //  1. when split occurs for tokenId = 5, first check if delegate is set, if yes, delegate token id 5(with total amount) as well 
    // and delegate 6 as with 0 amount as well.
    function test_SplitProblem() public {
        escrow.enableSplit();
        address alice = address(456);
        address bob = address(876);

        token.transfer(alice, 50e18);

        vm.startPrank(alice);
        token.approve(address(escrow), 50e18);
        uint256 tokenId = escrow.createLock(50e18);
        
        ivotesAdapter.setDelegateAddress(bob);
        uint256 newTokenId = escrow.split(tokenId, 10e18);
        vm.stopPrank();

        assertTrue(ivotesAdapter.tokenIsDelegated(tokenId));
        assertTrue(ivotesAdapter.tokenIsDelegated(newTokenId));
        
        // Shouldn't be 0. With current code, it is..
        console.log(ivotesAdapter.getPastVotes(bob, block.timestamp));

        vm.warp(block.timestamp + 1000);

        console.log(ivotesAdapter.getPastVotes(bob, block.timestamp));
    }

   
    // alice creates lock with amount 7225 (tokenId = 3)
    // alice creates lcok with amount 100 (tokenId = 4)
    // alice sets delegatee address to alice
    // alice merges tokenId 3 into 4

    // When merge occurs, it calls:
    // _moveDelegateVotes(alice, address(0), 3, LockedBalance(0, 0));

    // This gets to ivotesAdapter. Checks if (fromDelegatee != address(0)) which holds true because fromDelegatee is Bob.
    // and then does `numberOfDelegatedTokens[_from]--;`. Alice doesn't yet have delegated any tokens, so numberOfDelegatedTokens[alice] is 0.
    // It tries to decremenet, hence underflow.

    // Solution is to add the following in moveDelegateVotes..
    // if(tokenIsDelegated(_tokenId)) { numberOfDelegatedTokens[_from]--;}
    function test_sdlasdka() public {
        escrow.enableSplit();
        address alice = address(456);
        address bob = address(876);

        token.transfer(alice, 50e18);

        vm.startPrank(alice);
        token.approve(address(escrow), 50e18);

        uint256 from = escrow.createLock(7225);
        uint256 to = escrow.createLock(100);
        ivotesAdapter.setDelegateAddress(bob);

        escrow.merge(from, to);
        
        vm.stopPrank();
    }

    // Scenario:
    // alice creates lock tokenId = 1 (amount = 50)
    // alice sets delegate to bob 
    // alice creates lock tokenId = 2 (amount = 70) (bob now has 70 in escrowIVotesAdapter)
    // alice merges 1 into 2.
    // note that 1 is not delegated and 2 is. 
    // The current code only tries to set tokenId  = 1 as delegated false, nothing else. see (merge).
    // votingPower after the merge on tokenId = 2 must be 120. but getPastVotes on IvotesAdapter is 70.

    // Solution for this is the following:
    // call `moveDelegateVotes` and if delegate set, then delegate tokenId = 1 with its full amount. so ivotesadapter gets updated as 70(was) + 50(new)
    // then we call another moveDelegateVotes(with empty amount) to set tokenId = 1 non-delegated.
    // in merge:
    // _moveDelegateVotes(address(0), ownerFrom, _from, LockedBalance(oldLockedFrom.amount, oldLockedFrom.start));
    // _moveDelegateVotes(ownerFrom, address(0), _from, LockedBalance(0, 0))
    function test_kkk() public {
        address alice = address(456);
        address bob = address(876);

        token.transfer(alice, 120e18);

        vm.startPrank(alice);
        token.approve(address(escrow), 120e18);

        uint256 tokenId1 = escrow.createLock(50e18);
        ivotesAdapter.setDelegateAddress(bob);
        uint256 tokenId2 = escrow.createLock(70e18);
        escrow.merge(tokenId1, tokenId2);
        
        vm.stopPrank();

        console.log(escrow.votingPower(tokenId2), ivotesAdapter.getPastVotes(bob, block.timestamp));
    }

    // So see prev issue above and fix we did. So merge now contains two calls. While it fixed the prev problem, it raised new one.
    // Scenario:
    // Alice creates lock tokenId = 1
    // Alice creates lock tokenId = 2
    // Alice sets delegatee to Bob
    // Alice merges 2 into 1.
    // With the new fix code, getPastVotes will return only tokenId = 1's power. The question though is:
    // a. should we actually store any vp in ivotesadapter for this scenario ? because none of the token were delegated, so maybe it must still stay 0.
    // b. Or we must give both token's power to Bob. This causes in merge to call `moveDelegateVotes` 3 times. 

}
