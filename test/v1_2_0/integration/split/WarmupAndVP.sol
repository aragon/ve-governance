pragma solidity ^0.8.17;

import {EscrowBase} from "../../base/EscrowBase.sol";

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

contract TestSplit_WarmUpAndVotingPower is
    IEscrowCurveTokenStorage,
    IEscrowCurveGlobalStorage,
    EscrowBase
{
    uint256 from;
    uint256 weekStart;

    function setUp() public override {
        super.setUp();

        super.mintAndApproveEscrow();

        // Start from 1, so weekStartTs and block.timestamp differ.
        vm.warp(1);

        from = escrow.createLock(Lock_1_Amount);
        weekStart = weekStartTs(block.timestamp);
        escrow.setEnableSplit(address(this), true);
    }

    modifier givenWarmupPeriodLessThanMaxTime() {
        warmupPeriod = uint48(maxTime - 100);
        curve.setWarmupPeriod(uint48(warmupPeriod));
        _;
    }

    modifier givenWarmupPeriodGreaterThanMaxTime() {
        warmupPeriod = uint48(maxTime + 100);
        curve.setWarmupPeriod(uint48(warmupPeriod));
        _;
    }

    function test_Split_BeforeWarmupPeriod_A() public givenWarmupPeriodLessThanMaxTime {
        uint256 value = Lock_1_Amount - 10e18;

        (uint256 tokenId1, uint256 tokenId2) = escrow.split(from, value);

        // Split should not cause any changes to the warmup.
        assertEq(escrow.votingPower(from), 0);
        assertEq(escrow.votingPower(tokenId1), 0);
        assertEq(escrow.votingPower(tokenId2), 0);
        assertFalse(curve.isWarm(from));
        assertFalse(curve.isWarm(tokenId1));
        assertFalse(curve.isWarm(tokenId2));

        // move after warmup time.
        // Warmup has been reached, so vp must be non-zero 
        // and isWarm true for new tokens.
        vm.warp(weekStart + warmupPeriod + 1 seconds);

        assertEq(escrow.votingPower(from), 0);
        assertEq(escrow.votingPower(tokenId1), bias(10e18, block.timestamp - weekStart));
        assertEq(escrow.votingPower(tokenId2), bias(value, block.timestamp - weekStart));
        assertFalse(curve.isWarm(from));
        assertTrue(curve.isWarm(tokenId1));
        assertTrue(curve.isWarm(tokenId2));
    }

    function test_Split_AfterWarmupPeriod() public givenWarmupPeriodLessThanMaxTime {
        vm.warp(block.timestamp + warmupPeriod + 1 seconds);

        uint256 value = Lock_1_Amount - 10e18;

        (uint256 tokenId1, uint256 tokenId2) = escrow.split(from, value);

        // Warmup has been reached, so vp must be non-zero 
        // and isWarm true for new tokens.
        assertEq(escrow.votingPower(from), 0);
        assertEq(escrow.votingPower(tokenId1), bias(10e18, block.timestamp - weekStart));
        assertEq(escrow.votingPower(tokenId2), bias(value, block.timestamp - weekStart));
        assertFalse(curve.isWarm(from));
        assertTrue(curve.isWarm(tokenId1));
        assertTrue(curve.isWarm(tokenId2));
    }

    function test_Split_BeforeWarmupPeriod_B() public givenWarmupPeriodGreaterThanMaxTime {
        uint256 currentTs = block.timestamp;

        uint256 value = Lock_1_Amount - 10e18;

        (uint256 tokenId1, uint256 tokenId2) = escrow.split(from, value);

        // Warmup has not been reached, so vp must be 0 
        // and isWarm false for all tokens.
        assertEq(escrow.votingPower(from), 0);
        assertEq(escrow.votingPower(tokenId1), 0);
        assertEq(escrow.votingPower(tokenId1), 0);
        assertFalse(curve.isWarm(from));
        assertFalse(curve.isWarm(tokenId1));
        assertFalse(curve.isWarm(tokenId2));

        vm.warp(weekStart + maxTime);

        // Warmup has not been reached, so vp must be 0 
        // and isWarm false for all tokens.
        assertEq(escrow.votingPower(from), 0);
        assertEq(escrow.votingPower(tokenId1), 0);
        assertEq(escrow.votingPower(tokenId2), 0);
        assertFalse(curve.isWarm(from));
        assertFalse(curve.isWarm(tokenId1));
        assertFalse(curve.isWarm(tokenId2));

        // Warmup has been reached, so vp must be non-zero 
        // and isWarm true for new tokens.
        vm.warp(currentTs + warmupPeriod + 1 seconds);
        assertEq(escrow.votingPower(tokenId1), bias(10e18, maxTime));
        assertEq(escrow.votingPower(tokenId2), bias(value, maxTime));
        assertFalse(curve.isWarm(from));
        assertTrue(curve.isWarm(tokenId1));
        assertTrue(curve.isWarm(tokenId2));
    }
}
