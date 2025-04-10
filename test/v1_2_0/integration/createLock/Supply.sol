pragma solidity ^0.8.17;

import {EscrowBase} from "../../base/EscrowBase.sol";

import {console2 as console} from "forge-std/console2.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig, MultisigSetup} from "@aragon/multisig/MultisigSetup.sol";
import {MockERC20} from "@mocks/MockERC20.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";

import {Clock, IClock, Lock, VotingEscrow, LinearIncreasingEscrow, IVotingEscrowIncreasing, IEscrowCurveIncreasing, IVotingEscrowIncreasing, IVotingEscrowCoreErrors, IMerge, ISplit, ILockedBalanceIncreasing, IEscrowCurveGlobalStorage, IEscrowCurveTokenStorage, IEscrowCurveGlobalStorage} from "../../versions.sol";

contract TestCreateLock_Supply is IEscrowCurveTokenStorage, IEscrowCurveGlobalStorage, EscrowBase {
    function setUp() public override {
        super.setUp();

        super.mintAndApproveEscrow();
    }

    function test_whenCreatingNewLock_no_existing_lock_ookkk() public {
        // Given: no prior locks existing
        // 1. total bias at block.timestamp must be amount + slope * (block.timestamp - weekStart)
        // 2. total bias at t must be amount + slope * (t - weekStart)
        // 3. total bias must be the same at end and end + `t` (i.e stops increasing)
        // 4. votingPower should be 0 during warmup and equal to bias after warmup

        uint256 tokenId = escrow.createLock(Lock_1_Amount);

        uint256 weekStartTs = weekStartTs(block.timestamp);
        uint256 endTs = weekStartTs + maxTime;
        uint256 currentTs = block.timestamp;

        // 1, 2, 3
        assertTotalSupply(currentTs, biasFP(Lock_1_Amount, currentTs - weekStartTs));
        assertTotalSupply(currentTs - 1, 0);
        assertTotalSupply(endTs, biasFP(Lock_1_Amount, endTs - weekStartTs));
        assertTotalSupply(endTs + 10, biasFP(Lock_1_Amount, endTs - weekStartTs));

        // 4
        assertEq(curve.isWarm(tokenId), false);
        assertVotingPower(tokenId, 0);

        vm.warp(weekStartTs + warmupPeriod);

        assertEq(curve.isWarm(tokenId), false);
        assertVotingPower(tokenId, 0);

        vm.warp(weekStartTs + warmupPeriod + 1);
        assertEq(curve.isWarm(tokenId), true);
        assertVotingPower(tokenId, biasFP(Lock_1_Amount, block.timestamp - weekStartTs));
    }

    function test_whenCreatingNewLock_existingLock_at_same_timestamp() public givenExistingLock {
        // Given: prior locks exists at the same timestamp
        // 1. total supply at block.timestamp must be both lock's bias till this point summed up.
        // 2. total supply before block.timestamp must be 0.
        // 3. total supply must be the same at end and end + `t` (i.e stops increasing)
        escrow.createLock(Lock_2_Amount);

        uint256 totalLockAmount = Lock_1_Amount + Lock_2_Amount;

        uint256 weekStartTs = weekStartTs(block.timestamp);
        uint256 endTs = weekStartTs + maxTime;
        uint256 currentTs = block.timestamp;

        // 1, 2, 3
        assertTotalSupply(currentTs, biasFP(totalLockAmount, currentTs - weekStartTs));
        assertTotalSupply(currentTs - 1, 0);
        assertTotalSupply(endTs, biasFP(totalLockAmount, endTs - weekStartTs));
        assertTotalSupply(endTs + 10, biasFP(totalLockAmount, endTs - weekStartTs));
    }

    function test_whenCreatingNewLock_existingLock_at_previous_week() public givenExistingLock {
        // Given: prior locks exists in the previous week.
        // 1. total supply at block.timestamp must be both lock's bias till this point summed up.
        // 2. total supply before block.timestamp must only include first lock's bias till this moment.
        // 3. total supply shouldn't include the increase of first lock's bias after first lock's end.
        // 4. total supply shouldn't include the increase of second lock's bias after its end.
        vm.warp(block.timestamp + checkpointInterval);

        escrow.createLock(Lock_2_Amount);

        uint256 weekStartTs = weekStartTs(block.timestamp);
        uint256 currentTs = block.timestamp;

        int256 currentTotalBiasFP = biasFP(Lock_1_Amount, currentTs - Lock_1_start) +
            biasFP(Lock_2_Amount, currentTs - weekStartTs);

        // 1, 2
        assertTotalSupply(currentTs, currentTotalBiasFP);
        assertTotalSupply(currentTs - 1, biasFP(Lock_1_Amount, currentTs - 1 - Lock_1_start));

        uint256 Lock_1_end = Lock_1_start + maxTime;
        uint256 Lock_2_end = weekStartTs + maxTime;

        int256 Lock_1_MAX = biasFP(Lock_1_Amount, Lock_1_end - Lock_1_start);
        int256 LOCK_2_MAX = biasFP(Lock_2_Amount, Lock_2_end - weekStartTs);

        // 3
        assertTotalSupply(Lock_1_end, Lock_1_MAX + biasFP(Lock_2_Amount, Lock_1_end - weekStartTs));
        assertTotalSupply(
            Lock_1_end + 10,
            Lock_1_MAX + biasFP(Lock_2_Amount, Lock_1_end + 10 - weekStartTs)
        );

        // 4
        assertTotalSupply(Lock_2_end, Lock_1_MAX + LOCK_2_MAX);
        assertTotalSupply(Lock_2_end + 10, Lock_1_MAX + LOCK_2_MAX);
    }

    function test_whenCreatingNewLock_existingLock_ended() public givenExistingLock {
        // Given: prior locks exists and current timestamp is after its end date.
        // 1. total supply before currentTime must only include first lock's maxed out bias.
        // 2. total supply at block.timestamp must be both locked summed up, such that first lock's bias is constant reached max value.
        // 3. total supply must only include first lock's bias at first lock's end timestamp and shouldn't increase.
        // 4. total supply shouldn't include the increase of second lock's bias after its end.
        uint256 currentTime = block.timestamp + maxTime + 2 hours;
        vm.warp(currentTime);

        escrow.createLock(Lock_2_Amount);

        uint256 weekStartTs = weekStartTs(block.timestamp);
        uint256 currentTs = block.timestamp;

        uint256 Lock_1_end = Lock_1_start + maxTime;
        uint256 Lock_2_end = weekStartTs + maxTime;

        int256 Lock_1_MAX = biasFP(Lock_1_Amount, Lock_1_end - Lock_1_start);
        int256 Lock_2_MAX = biasFP(Lock_2_Amount, Lock_2_end - weekStartTs);

        int256 currentTotalBiasFP = biasFP(Lock_1_Amount, Lock_1_end - Lock_1_start) +
            biasFP(Lock_2_Amount, currentTs - weekStartTs);

        // 1, 2
        assertTotalSupply(currentTs, currentTotalBiasFP);
        assertTotalSupply(currentTs - 1, Lock_1_MAX);

        // 3
        assertTotalSupply(Lock_1_end, Lock_1_MAX);
        assertTotalSupply(Lock_1_end + 10, Lock_1_MAX);

        // 4
        assertTotalSupply(Lock_2_end, Lock_1_MAX + Lock_2_MAX);
        assertTotalSupply(Lock_2_end + 10, Lock_1_MAX + Lock_2_MAX);
    }
}
