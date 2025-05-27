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

    function test_Merge() public {
        escrow.merge(from, to);

        // Merge should not cause any changes to the warmup.
        assertTrue(curve.isWarm(from));

        assertEq(escrow.votingPower(from), 0);
        assertEq(
            escrow.votingPower(to),
            bias(Lock_1_Amount, block.timestamp - weekStart) +
                bias(Lock_2_Amount, block.timestamp - weekStart)
        );
    }
}
