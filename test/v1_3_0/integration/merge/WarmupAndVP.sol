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

contract TestMerge_WarmUpAndVotingPower is
    IEscrowCurveTokenStorage,
    IEscrowCurveGlobalStorage,
    EscrowBase
{
    uint256 from;
    uint256 to;
    uint256 weekStart;

    function setUp() public override {
        super.setUp();

        super.mintAndApproveEscrow();

        // Start from 1, so weekStartTs and block.timestamp differ.
        vm.warp(1);

        from = escrow.createLock(Lock_1_Amount);
        to = escrow.createLock(Lock_2_Amount);
        weekStart = weekStartTs(block.timestamp);
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

    function test_Merge_BeforeWarmupPeriod_A() public givenWarmupPeriodLessThanMaxTime {
        escrow.merge(from, to);

        // Merge should not cause any changes to the warmup.
        assertEq(escrow.votingPower(from), 0);
        assertEq(escrow.votingPower(to), 0);
        assertFalse(curve.isWarm(from));
        assertFalse(curve.isWarm(to));

        // move after warmup time.
        // Warmup has been reached, so vp must be non-zero
        // and isWarm true for `to`.
        vm.warp(weekStart + warmupPeriod + 1 seconds);

        assertEq(escrow.votingPower(from), 0);
        assertEq(
            escrow.votingPower(to),
            bias(Lock_1_Amount, block.timestamp - weekStart) +
                bias(Lock_2_Amount, block.timestamp - weekStart)
        );
        assertFalse(curve.isWarm(from));
        assertTrue(curve.isWarm(to));
    }

    function test_Merge_AfterWarmupPeriod() public givenWarmupPeriodLessThanMaxTime {
        vm.warp(block.timestamp + warmupPeriod + 1 seconds);

        escrow.merge(from, to);

        // Warmup has been reached, so vp must be non-zero
        // and isWarm true for `to`.
        assertEq(escrow.votingPower(from), 0);
        assertEq(
            escrow.votingPower(to),
            bias(Lock_1_Amount, block.timestamp - weekStart) +
                bias(Lock_2_Amount, block.timestamp - weekStart)
        );
        assertFalse(curve.isWarm(from));
        assertTrue(curve.isWarm(to));
    }

    function test_Merge_BeforeWarmupPeriod_B() public givenWarmupPeriodGreaterThanMaxTime {
        uint256 currentTs = block.timestamp;

        escrow.merge(from, to);

        // Warmup has not been reached, so vp must be 0
        // and isWarm false.
        assertEq(escrow.votingPower(from), 0);
        assertEq(escrow.votingPower(to), 0);

        vm.warp(weekStart + maxTime);

        // Warmup has not been reached, so vp must be 0
        // and isWarm false.
        assertEq(escrow.votingPower(from), 0);
        assertEq(escrow.votingPower(to), 0);
        assertFalse(curve.isWarm(from));
        assertFalse(curve.isWarm(to));

        // Warmup has been reached, so vp must be non-zero
        // and isWarm true for `to`.
        vm.warp(currentTs + warmupPeriod + 1 seconds);
        assertEq(
            escrow.votingPower(to),
            bias(Lock_1_Amount, maxTime) + bias(Lock_2_Amount, maxTime)
        );
        assertFalse(curve.isWarm(from));
        assertTrue(curve.isWarm(to));
    }
    
}
