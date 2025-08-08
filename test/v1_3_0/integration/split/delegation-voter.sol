pragma solidity ^0.8.17;

import {EscrowBase, IAddressGaugeVote} from "../../base/EscrowBase.sol";
import {console2 as console} from "forge-std/console2.sol";

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
    IGaugeVote
} from "../../versions.sol";

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

        // super.mintAndApproveEscrow(type(uint256).max);

        vm.warp(2 weeks + 1 hours + 1);
        // voter.createGauge(gauge, "metadata");
        // escrow.enableSplit();
    }

    function test_Split_CorrectlyUpdatesDelegationAndVotes() public {
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

    function testFuzz_Split_WhenTokenIsNotDelegated(uint192 _amount) public {
        uint256 minDeposit = 100;
        escrow.setMinDeposit(minDeposit);
        _approve(_amount, minDeposit);

        vm.startPrank(alice);
        uint256 tokenId1 = escrow.createLock(_amount);

        assertFalse(ivotesAdapter.tokenIsDelegated(tokenId1));

        escrow.split(tokenId1, minDeposit);
        assertEq(ivotesAdapter.getPastVotes(bob, block.timestamp), 0);

        assertFalse(ivotesAdapter.tokenIsDelegated(tokenId1));
        assertFalse(ivotesAdapter.tokenIsDelegated(tokenId1 + 1));
        assertEq(ivotesAdapter.numberOfDelegatedTokens(alice), 0);
        vm.stopPrank();
    }

    function testFuzz_Split_WhenTokenIsDelegated(uint192 _amount) public {
        uint256 minDeposit = 100;
        escrow.setMinDeposit(minDeposit);
        _approve(_amount, minDeposit);

        vm.startPrank(alice);
        ivotesAdapter.setDelegateAddress(bob);
        uint256 tokenId1 = escrow.createLock(_amount);

        assertTrue(ivotesAdapter.tokenIsDelegated(tokenId1));

        escrow.split(tokenId1, minDeposit);
        assertEq(
            ivotesAdapter.getPastVotes(bob, block.timestamp),
            bias(_amount, block.timestamp - weekStartTs(block.timestamp))
        );

        assertTrue(ivotesAdapter.tokenIsDelegated(tokenId1));
        assertTrue(ivotesAdapter.tokenIsDelegated(tokenId1 + 1));
        assertEq(ivotesAdapter.numberOfDelegatedTokens(alice), 2);
        vm.stopPrank();
    }

    function _approve(uint256 _amount, uint256 _minDeposit) private {
        vm.assume(_amount >= _minDeposit);
        token.transfer(alice, _amount);

        vm.prank(alice);
        token.approve(address(escrow), _amount);
    }

    function _approve(address _who, uint256 _amount) private {
        token.transfer(_who, _amount);

        vm.prank(_who);
        token.approve(address(escrow), _amount);
    }

    function test_fuck() public {
        address alice = address(0x000000000000000000000000000000000000000d);
        address bob = address(0x000000000000000000000000000000000000000F);

        vm.prank(alice);
        ivotesAdapter.setDelegateAddress(bob);

        token.mint(alice, 79228162514264337593543950333);

        vm.startPrank(alice);
        token.approve(address(escrow), 79228162514264337593543950333);
        escrow.createLock(79228162514264337593543950333);
        vm.stopPrank();

        voter.createGauge(address(0x0000000000000000000000000000000000000016), "metadata");
        voter.createGauge(address(0x0000000000000000000000000000000000000014), "metadata");
        voter.createGauge(address(0x0000000000000000000000000000000000000019), "metadata");
        voter.createGauge(address(0x0000000000000000000000000000000000000015), "metadata");

        IGaugeVote.GaugeVote[] memory gaugeVotes = new IGaugeVote.GaugeVote[](4);
        gaugeVotes[0] = IGaugeVote.GaugeVote(1, address(0x0000000000000000000000000000000000000016));
        gaugeVotes[1] = IGaugeVote.GaugeVote(18446744073709551613, address(0x0000000000000000000000000000000000000014));
        gaugeVotes[2] = IGaugeVote.GaugeVote(7847948105712314, address(0x0000000000000000000000000000000000000019));
        gaugeVotes[3] = IGaugeVote.GaugeVote(451357228, address(0x0000000000000000000000000000000000000015));

        vm.prank(bob);
        voter.vote(gaugeVotes);

        console.log("123123124dkkdaks 999", voter.totalVotingPowerCast());

        vm.prank(alice);
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        ivotesAdapter.undelegate(ids);

        console.log("123123124dkkdaks 777", voter.totalVotingPowerCast());


        // 0x000000000000000000000000000000000000000d delegates to 0x000000000000000000000000000000000000000F
        // 0x000000000000000000000000000000000000000d creates lock with amount = 79228162514264337593543950333 (tokenId = 1)
        // 0x000000000000000000000000000000000000000F votes 
        // 0x000000000000000000000000000000000000000d undelegates tokenId = 1

    }
}
