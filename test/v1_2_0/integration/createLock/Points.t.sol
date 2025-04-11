pragma solidity ^0.8.17;

import {EscrowBase} from "../../base/EscrowBase.sol";

import {console2 as console} from "forge-std/console2.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig, MultisigSetup} from "@aragon/multisig/MultisigSetup.sol";
import {MockERC20} from "@mocks/MockERC20.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";

import {
    Clock,
    IClock,
    Lock,
    VotingEscrow,
    LinearIncreasingEscrow,
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

contract TestCreateLock_Points is IEscrowCurveTokenStorage, IEscrowCurveGlobalStorage, EscrowBase {
    function setUp() public override {
        super.setUp();

        super.mintAndApproveEscrow();
    }

    function test_whenCreatingNewLock_no_existing_lock() public {
        // Given: no prior locks existing
        // 1. should be a single entry point in token point and global point history
        // 2. timestamp, start, slope and bias must be correctly set on the token and global point.
        // 3. should schedule a slope change at weekStart + MAX_TIME
        uint256 currentTs = block.timestamp;
        uint256 weekStartTs = weekStartTs(currentTs);

        uint256 tokenId = escrow.createLock(Lock_1_Amount);

        // 1, 2
        assertTokenPoint(
            tokenId,
            1,
            biasFP(Lock_1_Amount, currentTs - weekStartTs),
            slopeFP(Lock_1_Amount),
            weekStartTs,
            currentTs
        );

        // 3
        assertEq(slopeChanges(weekStartTs + maxTime), slopeFP(Lock_1_Amount));
    }

    function test_whenCreatingNewLock_existingLock_at_same_timestamp() public givenExistingLock {
        // Given: prior locks exists at the same timestamp
        // 1. should be 2 entry point in global history and one entry point in each lock's token point
        // 2. timestamp on the token and global point should be block.timestamp and start must be current week
        // 3. bias and slope on the last global point must include both lock's bias till this point summed up.
        // 4. should schedule both slopes summed up at weekStart + MAX_TIME
        escrow.createLock(Lock_2_Amount);

        uint256 currentTs = block.timestamp;
        uint256 weekStartTs = weekStartTs(currentTs);

        // 1, 2, 3
        int256 token1BiasFP = biasFP(Lock_1_Amount, currentTs - weekStartTs);
        int256 token2BiasFP = biasFP(Lock_2_Amount, currentTs - weekStartTs);

        assertTokenPoint(1, 1, token1BiasFP, slopeFP(Lock_1_Amount), weekStartTs, currentTs);
        assertTokenPoint(2, 1, token2BiasFP, slopeFP(Lock_2_Amount), weekStartTs, currentTs);

        // 4
        assertEq(
            slopeChanges(weekStartTs + maxTime),
            slopeFP(Lock_1_Amount) + slopeFP(Lock_2_Amount)
        );
    }

    function test_whenCreatingNewLock_existingLock_at_previous_week() public givenExistingLock {
        // Given: prior locks exists in the previous week.
        // 1. should be 3 entry point in global history and one entry point in each lock's token point
        // 2. timestamp on the token and global point should be block.timestamp and start must be current week
        // 3. bias and slope on the last global point must include both lock's bias and slope summed up till this point.
        // 4. should schedule slope changes at their according end dates.
        vm.warp(block.timestamp + checkpointInterval);

        escrow.createLock(Lock_2_Amount);

        uint256 currentTs = block.timestamp;
        uint256 weekStartTs = weekStartTs(currentTs);

        // 1, 2, 3
        int256 token1BiasFP = biasFP(Lock_1_Amount, Lock_1_ts - Lock_1_start);
        int256 token2BiasFP = biasFP(Lock_2_Amount, currentTs - weekStartTs);

        assertTokenPoint(1, 1, token1BiasFP, slopeFP(Lock_1_Amount), Lock_1_start, Lock_1_ts);
        assertTokenPoint(2, 1, token2BiasFP, slopeFP(Lock_2_Amount), weekStartTs, currentTs);

        // 4
        assertEq(slopeChanges(Lock_1_start + maxTime), slopeFP(Lock_1_Amount));
        assertEq(slopeChanges(weekStartTs + maxTime), slopeFP(Lock_2_Amount));
    }

    function test_whenCreatingNewLock_existingLock_ended() public givenExistingLock {
        // Given: prior locks exists and current timestamp is after its end date.
        // 1. should be `X`(X = howmanyweeksbetween + 2) entry point in global history and one entry point in each lock's token point.
        // 2. timestamp on the token and global point should be block.timestamp and start must be current week
        // 3. slope on the last global point must only include 2nd lock's slope and bias must include first lock's max + second lock's bias till this point.
        // 4. should schedule slope changes at their according end dates.
        uint256 currentTime = block.timestamp + maxTime + 2 hours;
        vm.warp(currentTime);

        escrow.createLock(Lock_2_Amount);

        uint256 currentTs = block.timestamp;
        uint256 weekStartTs = weekStartTs(currentTs);

        uint256 Lock_1_end = Lock_1_start + maxTime;
        uint256 Lock_2_end = weekStartTs + maxTime;

        // 1, 2, 3
        int256 token1BiasFP = biasFP(Lock_1_Amount, Lock_1_ts - Lock_1_start);
        int256 token2BiasFP = biasFP(Lock_2_Amount, currentTs - weekStartTs);

        assertTokenPoint(1, 1, token1BiasFP, slopeFP(Lock_1_Amount), Lock_1_start, Lock_1_ts);
        assertTokenPoint(2, 1, token2BiasFP, slopeFP(Lock_2_Amount), weekStartTs, currentTs);

        // 4
        assertEq(slopeChanges(Lock_1_end), slopeFP(Lock_1_Amount));
        assertEq(slopeChanges(Lock_2_end), slopeFP(Lock_2_Amount));
    }
}
