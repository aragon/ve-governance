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
    
    function test_Split() public {
        uint256 value = 10e18;

        uint256 tokenId1 = escrow.split(from, value);

        // Split should not cause any changes to the warmup.
        assertTrue(curve.isWarm(from));
        assertTrue(curve.isWarm(tokenId1));

        assertEq(escrow.votingPower(from), bias(Lock_1_Amount - value, block.timestamp - weekStart));
        assertEq(escrow.votingPower(tokenId1), bias(value, block.timestamp - weekStart));
        assertTrue(curve.isWarm(from));
        assertTrue(curve.isWarm(tokenId1));
    }
}
