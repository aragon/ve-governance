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

contract TestCreateLock_WarmUpAndVotingPower is IEscrowCurveTokenStorage, IEscrowCurveGlobalStorage, EscrowBase {
    uint256 weekStart;

    function setUp() public override {
        super.setUp();

        super.mintAndApproveEscrow();

        // Start from 1, so weekStartTs and block.timestamp differ.
        vm.warp(1);
        weekStart = weekStartTs(block.timestamp);
    }

    modifier givenWarmupPeriodLessThanMaxTime() {
        if(maxTime != 0) {
            warmupPeriod = uint48(maxTime - 100);
        }
        
        curve.setWarmupPeriod(uint48(warmupPeriod));
        _;
    }

    modifier givenWarmupPeriodGreaterThanMaxTime() {
        warmupPeriod = uint48(maxTime + 100);
        curve.setWarmupPeriod(uint48(warmupPeriod));
        _;
    }

    function test_CreateLock_BeforeWarmupPeriod_A() public givenWarmupPeriodLessThanMaxTime {
        uint256 tokenId = escrow.createLock(Lock_1_Amount);
        
        uint256 weekStartTs = weekStartTs(block.timestamp);
        uint256 endTs = getEndTimestamp(weekStartTs, block.timestamp);

        // Warmup has not been reached, so vp must 
        // be 0 and isWarm false.
        assertEq(curve.isWarm(tokenId), false);
        assertVotingPower(tokenId, 0);
        
        // Warmup has not been reached, so vp must 
        // be 0 and isWarm false.
        vm.warp(weekStart + warmupPeriod);
        assertEq(curve.isWarm(tokenId), false);
        assertVotingPower(tokenId, 0);

        // Warmup has been reached, so vp must be non-zero
        // and isWarm true.
        vm.warp(weekStart + warmupPeriod + 1);
        assertEq(curve.isWarm(tokenId), true);
        assertVotingPower(tokenId, biasFP(Lock_1_Amount, block.timestamp - weekStart));

        if (endTs >= weekStartTs + warmupPeriod + 1) {
            int256 maxVotingPower = biasFP(Lock_1_Amount, maxTime);
            assertVotingPower(tokenId, weekStart + maxTime, maxVotingPower);
            assertVotingPower(tokenId, weekStart + maxTime + 10, maxVotingPower);
        }
    }

    function test_CreateLock_BeforeWarmupPeriod_B() public givenWarmupPeriodGreaterThanMaxTime {
        uint256 tokenId = escrow.createLock(Lock_1_Amount);

        // Warmup has not been reached, so vp must 
        // be 0 and isWarm false.
        assertFalse(curve.isWarm(tokenId));
        assertVotingPower(tokenId, 0);

        vm.warp(weekStart + maxTime);

        // Warmup has not been reached, so vp must 
        // be 0 and isWarm false.
        assertFalse(curve.isWarm(tokenId));
        assertVotingPower(tokenId, 0);

        // Warmup has been reached, so vp must be non-zero
        // and isWarm true.
        vm.warp(weekStart + warmupPeriod + 1 seconds);
        
        assertTrue(curve.isWarm(tokenId));
        assertVotingPower(tokenId, biasFP(Lock_1_Amount, maxTime));
    }
}
