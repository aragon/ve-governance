pragma solidity ^0.8.17;

import {console2 as console} from "forge-std/console2.sol";

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
    IEscrowCurveTokenStorage
} from "../../versions.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {EscrowBase} from "./EscrowBase.sol";

contract TestCreateLock is EscrowBase {
    
    function setUp() public override {
        super.setUp();
    }

    function test_whenCreatingNewLock_no_existing_lock() public {
        // Given: no prior locks existing
        // 1. should start lock at start of the current week(deposit interval)
        // 2. should be a single entry point in token point and global point history
        // 3. timestamp, start, slope and bias must be correctly set on the token and global point.
        // 4. total bias at block.timestamp must be amount + slope * (block.timestamp - weekStart)
        // 5. total bias at t must be amount + slope * (t - weekStart)
        // 6. total bias must be the same at end and end + `t` (i.e stops increasing)
        // 7. should schedule a slope change at weekStart + MAX_TIME
        // 8. votingPower should be 0 during warmup and equal to bias after warmup

        uint256 tokenId = escrow.createLock(Lock_1_Amount);
        (uint256 weekStartTs, uint256 endTs, uint256 currentTs) = getTimes();

        // 1
        ILockedBalanceIncreasing.LockedBalance memory lock = escrow.locked(tokenId);
        assertEq(lock.amount, Lock_1_Amount);
        assertEq(lock.start, weekStartTs);

        // 2
        assertEq(curve.globalPointLatestIndex(), 1);
        assertEq(curve.tokenPointLatestIndex(1), 1);

        // 3
        GlobalPoint memory p = curve.globalPointHistory(1);
        assertEq(p.writtenTs, currentTs);
        assertEq(p.bias, biasFP(Lock_1_Amount, currentTs - weekStartTs));
        assertEq(p.slope, slopeFP(Lock_1_Amount));

        // 4,5,6
        assertTotalSupply(currentTs, biasFP(Lock_1_Amount, currentTs - weekStartTs));
        assertTotalSupply(currentTs - 1, 0);
        assertTotalSupply(endTs, biasFP(Lock_1_Amount, endTs - weekStartTs));
        assertTotalSupply(endTs + 10, biasFP(Lock_1_Amount, endTs - weekStartTs));

        // 7
        assertEq(slopeChanges(endTs), slopeFP(Lock_1_Amount));

        // 8
        // assertVotingPower(tokenId, currentTs, 0);
        // assertEq(curve.isWarm(tokenId), false);
        // vm.warp(currentTs + warmupPeriod);
        // // assertVotingPower(tokenId, currentTs, 0);
        // // assertEq(curve.isWarm(tokenId), false);
        // vm.warp(currentTs + warmupPeriod + 3);
        // assertEq(curve.isWarm(tokenId), true);
        // assertVotingPower(tokenId, block.timestamp, biasFP(Lock_1_Amount, block.timestamp - weekStartTs));
    }

    function test_whenCreatingNewLock_existingLock_at_same_timestamp() public givenExistingLock {
        // Given: prior locks exists at the same timestamp
        // 1. should be 2 entry point in global history and one entry point in each lock's token point
        // 2. timestamp on the token and global point should be block.timestamp and start must be current week
        // 3. bias and slope on the last global point must include both lock's bias till this point summed up.
        // 4. total supply at block.timestamp must be both lock's bias till this point summed up.
        // 5. total supply before block.timestamp must be 0.
        // 6. total supply must be the same at end and end + `t` (i.e stops increasing)
        // 7. should schedule both slopes summed up at weekStart + MAX_TIME
        escrow.createLock(Lock_2_Amount);

        uint256 totalLockAmount = Lock_1_Amount + Lock_2_Amount;

        (uint256 weekStartTs, uint256 endTs, uint256 currentTs) = getTimes();

        // 1
        assertEq(curve.globalPointLatestIndex(), 2);
        assertEq(curve.tokenPointLatestIndex(1), 1);
        assertEq(curve.tokenPointLatestIndex(2), 1);

        // 2, 3
        GlobalPoint memory p = curve.globalPointHistory(2);
        assertEq(p.writtenTs, currentTs);
        assertEq(
            p.bias,
            biasFP(Lock_1_Amount, currentTs - weekStartTs) +
                biasFP(Lock_2_Amount, currentTs - weekStartTs)
        );

        assertEq(p.slope, slopeFP(Lock_1_Amount) + slopeFP(Lock_2_Amount));

        // 4, 5, 6
        assertTotalSupply(currentTs, biasFP(totalLockAmount, currentTs - weekStartTs));
        assertTotalSupply(currentTs - 1, 0);
        assertTotalSupply(endTs, biasFP(totalLockAmount, endTs - weekStartTs));
        assertTotalSupply(endTs + 10, biasFP(totalLockAmount, endTs - weekStartTs));

        // 7
        assertEq(slopeChanges(endTs), slopeFP(Lock_1_Amount) + slopeFP(Lock_2_Amount));
    }

    function test_whenCreatingNewLock_existingLock_at_previous_week() public givenExistingLock {
        // Given: prior locks exists in the previous week.
        // 1. should be 3 entry point in global history and one entry point in each lock's token point
        // 2. timestamp on the token and global point should be block.timestamp and start must be current week
        // 3. bias and slope on the last global point must include both lock's bias and slope summed up till this point.
        // 4. total supply at block.timestamp must be both lock's bias till this point summed up.
        // 5. total supply before block.timestamp must only include first lock's bias till this moment.
        // 6. total supply shouldn't include the increase of first lock's bias after first lock's end.
        // 7. total supply shouldn't include the increase of second lock's bias after its end.
        // 8. should schedule slope changes at their according end dates.
        vm.warp(block.timestamp + checkpointInterval);

        escrow.createLock(Lock_2_Amount);

        (uint256 weekStartTs, uint256 endTs, uint256 currentTs) = getTimes();

        // 1
        // epoch is 3 because there's a week between the locks
        // which must be updated upon 2nd lock's insert.
        assertEq(curve.globalPointLatestIndex(), 3);
        assertEq(curve.tokenPointLatestIndex(1), 1);
        assertEq(curve.tokenPointLatestIndex(2), 1);

        int256 currentTotalBiasFP = biasFP(Lock_1_Amount, currentTs - Lock_1_start) +
            biasFP(Lock_2_Amount, currentTs - weekStartTs);

        // 2, 3
        GlobalPoint memory p = curve.globalPointHistory(3);
        assertEq(p.writtenTs, currentTs);
        assertEq(p.bias, currentTotalBiasFP);
        assertEq(p.slope, slopeFP(Lock_1_Amount) + slopeFP(Lock_2_Amount));

        // 4, 5
        assertTotalSupply(currentTs, currentTotalBiasFP);
        assertTotalSupply(currentTs - 1, biasFP(Lock_1_Amount, currentTs - 1 - Lock_1_start));

        uint256 Lock_1_end = Lock_1_start + maxTime;
        uint256 Lock_2_end = weekStartTs + maxTime;

        int256 Lock_1_MAX = biasFP(Lock_1_Amount, Lock_1_end - Lock_1_start);
        int256 LOCK_2_MAX = biasFP(Lock_2_Amount, Lock_2_end - weekStartTs);

        // 6
        assertTotalSupply(Lock_1_end, Lock_1_MAX + biasFP(Lock_2_Amount, Lock_1_end - weekStartTs));
        assertTotalSupply(
            Lock_1_end + 10,
            Lock_1_MAX + biasFP(Lock_2_Amount, Lock_1_end + 10 - weekStartTs)
        );

        // 7
        assertTotalSupply(Lock_2_end, Lock_1_MAX + LOCK_2_MAX);
        assertTotalSupply(Lock_2_end + 10, Lock_1_MAX + LOCK_2_MAX);

        // 8
        assertEq(slopeChanges(Lock_1_end), slopeFP(Lock_1_Amount));
        assertEq(slopeChanges(Lock_2_end), slopeFP(Lock_2_Amount));
    }

    function test_whenCreatingNewLock_existingLock_ended() public givenExistingLock {
        // Given: prior locks exists and current timestamp is after its end date.
        // 1. should be `X`(X = howmanyweeksbetween + 2) entry point in global history and one entry point in each lock's token point.
        // 2. timestamp on the token and global point should be block.timestamp and start must be current week
        // 3. slope on the last global point must only include 2nd lock's slope and bias must include first lock's max + second lock's bias till this point.
        // 4. total supply before currentTime must only include first lock's maxed out bias.
        // 5. total supply at block.timestamp must be both locked summed up, such that first lock's bias is constant reached max value.
        // 6. total supply must only include first lock's bias at first lock's end timestamp and shouldn't increase.
        // 7. total supply shouldn't include the increase of second lock's bias after its end.
        // 8. should schedule slope changes at their according end dates.
        uint256 currentTime = block.timestamp + maxTime + 2 hours;
        vm.warp(currentTime);

        escrow.createLock(Lock_2_Amount);

        (uint256 weekStartTs, uint256 endTs, uint256 currentTs) = getTimes();

        // Calculate how many weeks between our locks + 2 as last lock's record and new lock's record.
        uint256 lastEpoch = (currentTime - Lock_1_start) / checkpointInterval + 2;

        uint256 Lock_1_end = Lock_1_start + maxTime;
        uint256 Lock_2_end = weekStartTs + maxTime;

        // 1
        // epoch is `howManyWeeksBetween + 2`. We add 2 because the first lock and last lock.
        assertEq(curve.globalPointLatestIndex(), lastEpoch);
        assertEq(curve.tokenPointLatestIndex(1), 1);
        assertEq(curve.tokenPointLatestIndex(2), 1);

        int256 currentTotalBiasFP = biasFP(Lock_1_Amount, Lock_1_end - Lock_1_start) +
            biasFP(Lock_2_Amount, currentTs - weekStartTs);

        // 2, 3
        GlobalPoint memory p = curve.globalPointHistory(lastEpoch);
        assertEq(p.writtenTs, currentTs);
        assertEq(p.bias, currentTotalBiasFP); 
        assertEq(p.slope, slopeFP(Lock_2_Amount));

        int256 Lock_1_MAX = biasFP(Lock_1_Amount, Lock_1_end - Lock_1_start);
        int256 Lock_2_MAX = biasFP(Lock_2_Amount, Lock_2_end - weekStartTs);

        // 4, 5
        assertTotalSupply(currentTs, currentTotalBiasFP);
        assertTotalSupply(currentTs - 1, Lock_1_MAX);

        // 6
        assertTotalSupply(Lock_1_end, Lock_1_MAX);
        assertTotalSupply(Lock_1_end + 10, Lock_1_MAX);

        // 7
        assertTotalSupply(Lock_2_end, Lock_1_MAX + Lock_2_MAX);
        assertTotalSupply(Lock_2_end + 10, Lock_1_MAX + Lock_2_MAX);

        // 8
        assertEq(slopeChanges(Lock_1_end), slopeFP(Lock_1_Amount));
        assertEq(slopeChanges(Lock_2_end), slopeFP(Lock_2_Amount));
    }
}
