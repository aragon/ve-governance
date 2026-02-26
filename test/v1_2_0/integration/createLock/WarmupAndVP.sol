pragma solidity ^0.8.17;

import {EscrowBase} from "../../base/EscrowBase.sol";
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
    IEscrowCurveGlobalStorage
} from "../../versions.sol";

contract TestCreateLock_WarmUpAndVotingPower is
    IEscrowCurveTokenStorage,
    IEscrowCurveGlobalStorage,
    EscrowBase
{
    uint256 weekStart;

    function setUp() public override {
        super.setUp();

        super.mintAndApproveEscrow();

        // Start from 1, so weekStartTs and block.timestamp differ.
        vm.warp(1);
        weekStart = weekStartTs(block.timestamp);
    }

    function test_CreateLock() public {
        uint256 tokenId = escrow.createLock(Lock_1_Amount);
        
        assertVotingPower(tokenId, biasFP(Lock_1_Amount, block.timestamp - weekStart));

        uint256 endTs = getEndTimestamp(weekStart, block.timestamp);
        int256 maxVotingPower = biasFP(Lock_1_Amount, maxTime);
        assertVotingPower(tokenId, endTs, maxVotingPower);
        assertVotingPower(tokenId, endTs + 10, maxVotingPower);
    }
}
