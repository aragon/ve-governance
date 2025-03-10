pragma solidity ^0.8.17;

import {console2 as console} from "forge-std/console2.sol";

import {QuadraticIncreasingEscrow, IVotingEscrow, IEscrowCurve} from "src/escrow/increasing/QuadraticIncreasingEscrow.sol";
import {IVotingEscrowIncreasing, IVotingEscrowCoreErrors, IMerge, ISplit, ILockedBalanceIncreasing} from "src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol";
import {IEscrowCurveGlobalStorage, IEscrowCurveTokenStorage} from "src/escrow/increasing/interfaces/IEscrowCurveIncreasing.sol";

import {VotingEscrow} from "src/escrow/increasing/VotingEscrowIncreasing.sol";
import {Lock} from "src/escrow/increasing/Lock.sol";

import {Test} from "forge-std/Test.sol";
import {SafeCastUpgradeable as SafeCast} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

import {CurveConstantLib} from "@libs/CurveConstantLib.sol";
import {Clock} from "../src/clock/Clock.sol";
import {IClock} from "../src/clock/IClock.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {ProxyLib} from "@libs/ProxyLib.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract TestEscrow is Test, IEscrowCurveGlobalStorage, IEscrowCurveTokenStorage {
    using ProxyLib for address;
    using SafeCast for uint256;

    uint208 internal TOKEN_5K = 5e21;

    uint256 internal DAY = 86400;

    QuadraticIncreasingEscrow internal curve;
    VotingEscrow internal escrow;
    Clock internal clock;

    uint208 internal Lock_1_Amount = 50e18;
    uint208 internal Lock_2_Amount = 30e18;

    uint256 internal Lock_1_ts;
    uint256 internal Lock_1_start;

    uint256 internal Lock_2_ts;
    uint256 internal Lock_2_start;

    address public sender = address(123);

    uint256 public checkpointInterval;
    uint256 public maxTime;

    function lockedBalance(
        uint208 amount,
        uint48 start
    ) public pure returns (ILockedBalanceIncreasing.LockedBalance memory) {
        return ILockedBalanceIncreasing.LockedBalance(amount, start);
    }

    function getTimes()
        private
        view
        returns (uint256 weekStartTs, uint256 endTs, uint256 currentTs)
    {
        weekStartTs = (block.timestamp / checkpointInterval) * checkpointInterval;
        endTs = weekStartTs + maxTime;
        currentTs = block.timestamp;
    }

    function slopeFP(uint256 _amount) private view returns (int256) {
        return int256(_amount * (1e18 / maxTime));
    }

    function biasFP(uint256 _amount, uint256 _duration) private view returns (int256) {
        return int256(_amount * 1e18 + ((_amount * (1e18 / maxTime)) * _duration));
    }

    function bias(uint256 _amount, uint256 _duration) private view returns (int256 bias_) {
        return biasFP(_amount, _duration) / 1e18;
    }

    function assertTotalSupply(uint256 _t, int256 _amountFP) private view {
        assertEq(curve.supplyAt(_t), uint256(_amountFP / 1e18));
    }

    function setUp() public {
        DAO _dao = DAO(payable(new ERC1967Proxy(address(new DAO()), bytes(""))));
        _dao.initialize({
            _metadata: bytes(""),
            _initialOwner: address(this),
            _trustedForwarder: address(0),
            daoURI_: "ipfs://"
        });

        clock = new Clock();
        checkpointInterval = clock.checkpointInterval();
        maxTime = IClock(clock).epochDuration() * CurveConstantLib.MAX_EPOCHS;

        MockERC20 token = new MockERC20();

        // deploy escrow proxy
        escrow = VotingEscrow(
            address(new VotingEscrow()).deployUUPSProxy(
                abi.encodeCall(
                    VotingEscrow.initialize,
                    (address(token), address(_dao), address(clock), 0)
                )
            )
        );

        // deploy curve proxy
        curve = QuadraticIncreasingEscrow(
            address(new QuadraticIncreasingEscrow()).deployUUPSProxy(
                abi.encodeCall(
                    QuadraticIncreasingEscrow.initialize,
                    (address(escrow), address(_dao), 0, address(clock))
                )
            )
        );

        _dao.grant({
            _who: address(this),
            _where: address(escrow),
            _permissionId: escrow.ESCROW_ADMIN_ROLE()
        });

        token.mint(sender, 10000000e18);

        escrow.setCurve(address(curve));
        escrow.setLockNFT(
            address(address(new Lock())).deployUUPSProxy(
                abi.encodeWithSelector(
                    Lock.initialize.selector,
                    address(escrow),
                    "nameoo",
                    "symbol",
                    address(_dao)
                )
            )
        );

        vm.startPrank(sender);
        token.approve(address(escrow), 10000000e18);
    }

    modifier givenExistingLock() {
        vm.warp(block.timestamp + 1 hours);
        uint256 tokenId = escrow.createLock(Lock_1_Amount);

        Lock_1_ts = block.timestamp;
        Lock_1_start = (block.timestamp / checkpointInterval) / checkpointInterval;
        _;
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
        assertEq(p.ts, currentTs);
        assertEq(p.bias, biasFP(Lock_1_Amount, currentTs - weekStartTs));
        assertEq(p.slope, slopeFP(Lock_1_Amount));

        // 4,5,6
        assertTotalSupply(currentTs, biasFP(Lock_1_Amount, currentTs - weekStartTs));
        assertTotalSupply(currentTs - 1, 0);
        assertTotalSupply(endTs, biasFP(Lock_1_Amount, endTs - weekStartTs));
        assertTotalSupply(endTs + 10, biasFP(Lock_1_Amount, endTs - weekStartTs));

        // 7
        assertEq(curve.slopeChanges(endTs), slopeFP(Lock_1_Amount));

        // 8
        // TODO:
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
        assertEq(p.ts, currentTs);
        assertEq(
            p.bias,
            biasFP(Lock_1_Amount, currentTs - weekStartTs) +
                biasFP(Lock_2_Amount, currentTs - weekStartTs)
        );

        // assertEq(p.start, weekStartTs); TODO: check it on `locked()`
        assertEq(p.slope, slopeFP(Lock_1_Amount) + slopeFP(Lock_2_Amount));

        // 4, 5, 6
        assertTotalSupply(currentTs, biasFP(totalLockAmount, currentTs - weekStartTs));
        assertTotalSupply(currentTs - 1, 0);
        assertTotalSupply(endTs, biasFP(totalLockAmount, endTs - weekStartTs));
        assertTotalSupply(endTs + 10, biasFP(totalLockAmount, endTs - weekStartTs));

        // 7
        assertEq(curve.slopeChanges(endTs), slopeFP(Lock_1_Amount) + slopeFP(Lock_2_Amount));
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
        assertEq(p.ts, currentTs);
        assertEq(p.bias, currentTotalBiasFP);
        // assertEq(p.start, weekStartTs); TODO: check it on `locked()`
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
        assertEq(curve.slopeChanges(Lock_1_end), slopeFP(Lock_1_Amount));
        assertEq(curve.slopeChanges(Lock_2_end), slopeFP(Lock_2_Amount));
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
        assertEq(p.ts, currentTs);
        assertEq(p.bias, currentTotalBiasFP);
        // assertEq(p.start, weekStartTs); TODO: check it on `locked()`
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
        assertEq(curve.slopeChanges(Lock_1_end), slopeFP(Lock_1_Amount));
        assertEq(curve.slopeChanges(Lock_2_end), slopeFP(Lock_2_Amount));
    }

    // ================== MERGE ============================
    function test_shouldRevert_IfNotMatureAndDifferentStart() public {
        uint256 from = escrow.createLock(Lock_1_Amount);

        // Warp so start dates end up different..
        vm.warp(block.timestamp + checkpointInterval);
        uint256 to = escrow.createLock(Lock_2_Amount);

        //reverts as start dates are different and tokens are not mature.
        vm.expectRevert(
            abi.encodeWithSelector(IMerge.CannotMerge.selector, from, to)
        );
        escrow.merge(from, to);
    }

    function test_shouldRevert_IfSenderIsNotApprovedOrOwner() public {
        uint256 from = escrow.createLock(Lock_1_Amount);
        uint256 to = escrow.createLock(Lock_2_Amount);

        vm.startPrank(address(999));
        vm.expectRevert(IVotingEscrowCoreErrors.NotApprovedOrOwner.selector);
        escrow.merge(from, to);
    }

    function test_shouldRevert_BothNFTsAreSame() public {
        uint256 from = escrow.createLock(Lock_1_Amount);

        vm.expectRevert(IVotingEscrowCoreErrors.SameNFT.selector);
        escrow.merge(from, from);
    }

    function test_Merge_WhenNotMature_SameStartDate() public {
        // 1. on `from` token point, bias and slope must become 0. `start` should stay the same and current timestamp updated.
        // 2. on `to` token point, bias and slope must include both token's bias and slope. `start` should stay the same and current timestamp updated.
        // 3. total supply at current time include both tokens' bias till this moment.
        // 4. total supply at current time + t should increase from the totalSupply at current time.
        // 5. total supply at `end` and `end + X` must be the same(sum of maxed out values of both tokens) - it should stop increasing.
        // 6. Since `to` tokens is not mature yet, end is in the future, so slopeChanges must still contain the sum of both slopes.
        uint256 from = escrow.createLock(Lock_1_Amount);
        uint256 to = escrow.createLock(Lock_2_Amount);

        (uint256 weekStartTs, uint256 endTs, uint256 currentTs) = getTimes();

        // TODO:GIORGI
        // vm.expectEmit();
        // emit IMerge.Merged(sender, from, to, Lock_1_Amount, Lock_2_Amount, Lock_1_Amount + Lock_2_Amount);

        escrow.merge(from, to);

        uint256 fromLatestEpoch = curve.tokenPointLatestIndex(from);
        assertEq(fromLatestEpoch, 1);

        // 1
        TokenPoint memory fromP = curve.tokenPointHistory(from, fromLatestEpoch);

        assertEq(fromP.coefficients[0], 0);
        assertEq(fromP.coefficients[1], 0);
        // assertEq(fromP.start, weekStartTs); TODO: check it on `locked()`
        assertEq(fromP.ts, currentTs);

        // 2
        // since merge occured in the same block as `createLock`,
        // it should not cause extra epoch for user.
        uint256 toLatestEpoch = curve.tokenPointLatestIndex(to);
        assertEq(toLatestEpoch, 1);

        TokenPoint memory toP = curve.tokenPointHistory(to, toLatestEpoch);

        int256 currentTotalBiasFP = biasFP(Lock_1_Amount, currentTs - weekStartTs) +
            biasFP(Lock_2_Amount, currentTs - weekStartTs);

        assertEq(toP.coefficients[0], currentTotalBiasFP);
        assertEq(toP.coefficients[1], slopeFP(Lock_1_Amount) + slopeFP(Lock_2_Amount));
        // assertEq(toP.start, weekStartTs); TODO: check it on `locked()`
        assertEq(toP.ts, currentTs);

        uint256 end = weekStartTs + maxTime;
        int256 LOCK_1_MAX = biasFP(Lock_1_Amount, end - weekStartTs);
        int256 LOCK_2_MAX = biasFP(Lock_2_Amount, end - weekStartTs);

        // 3
        assertTotalSupply(currentTs, currentTotalBiasFP);

        // 4
        assertTotalSupply(
            currentTs + 10,
            currentTotalBiasFP + slopeFP(Lock_1_Amount) * 10 + slopeFP(Lock_2_Amount) * 10
        );

        // 5
        assertTotalSupply(end, LOCK_1_MAX + LOCK_2_MAX);
        assertTotalSupply(end + 10, LOCK_1_MAX + LOCK_2_MAX);

        // 6
        assertEq(curve.slopeChanges(end), slopeFP(Lock_1_Amount) + slopeFP(Lock_2_Amount));
    }

    function test_Merge_WhenMature_SameStartDate() public {
        // 1. on `from` token point, bias and slope must become 0. `start` should stay the same and current timestamp updated.
        // 2. on `to` token point, bias must be the sum of both token's maxed out values. Slope must be 0 as it's already maxed out.
        // `start` should stay the same and current timestamp updated.
        // 3. total supply at current time must be sum of both token's maxed out values.
        // 4. total supply at currentTime and `currentTime + X` must be the same(sum of maxed out values of both tokens)
        // 5. last global point must have slope 0 and bias as sum of both token's maxed out values.
        // 6. Since both have the same end and is in the past, slopeChanges must still be the same of both slopes.
        uint256 from = escrow.createLock(Lock_1_Amount);
        uint256 to = escrow.createLock(Lock_2_Amount);

        (uint256 weekStartTs, uint256 endTs, ) = getTimes();

        uint256 end = weekStartTs + maxTime;
        int256 LOCK_1_MAX = biasFP(Lock_1_Amount, end - weekStartTs);
        int256 LOCK_2_MAX = biasFP(Lock_2_Amount, end - weekStartTs);

        vm.warp(end + 1 hours);
        escrow.merge(from, to);

        uint256 currentTs = block.timestamp;

        uint256 fromLatestEpoch = curve.tokenPointLatestIndex(from);
        assertEq(fromLatestEpoch, 2);

        // 1
        TokenPoint memory fromP = curve.tokenPointHistory(from, fromLatestEpoch);

        assertEq(fromP.coefficients[0], 0);
        assertEq(fromP.coefficients[1], 0);
        // assertEq(fromP.start, weekStartTs); TODO: check it on `locked()`
        assertEq(fromP.ts, currentTs);

        // 2
        // since merge occured in the different block than `createLock`,
        // it should  cause extra epoch for user.
        uint256 toLatestEpoch = curve.tokenPointLatestIndex(to);
        assertEq(toLatestEpoch, 2);

        TokenPoint memory toP = curve.tokenPointHistory(to, toLatestEpoch);

        int256 currentTotalBiasFP = LOCK_1_MAX + LOCK_2_MAX;

        assertEq(toP.coefficients[0], currentTotalBiasFP);
        assertEq(toP.coefficients[1], 0);
        // assertEq(toP.start, weekStartTs); TODO: check it on `locked()`
        assertEq(toP.ts, currentTs);

        // 3, 4
        assertTotalSupply(currentTs - 1, currentTotalBiasFP);
        assertTotalSupply(currentTs, currentTotalBiasFP);
        assertTotalSupply(currentTs + 1, currentTotalBiasFP);

        // 5
        GlobalPoint memory lastPoint = curve.globalPointHistory(curve.globalPointLatestIndex());

        assertEq(lastPoint.slope, 0);
        assertEq(lastPoint.bias, currentTotalBiasFP);
        assertEq(lastPoint.ts, currentTs);
        // assertEq(lastPoint.start, (currentTs / checkpointInterval) * checkpointInterval); // TODO:GIORGI on the global points, we also store something like lastPoint.start = _newLocked.start
        // in this specific scenario, lastPoint.start becomes the `to` token's start which is in the past. does this make sense at all ?

        // 6
        assertEq(curve.slopeChanges(end), slopeFP(Lock_1_Amount) + slopeFP(Lock_2_Amount));
    }

    function test_Merge_WhenMature_DifferentStartDates() public {
        // 1. on `from` token point, bias and slope must become 0. `start` should stay the same and current timestamp updated.
        // 2. on `to` token point, bias must be the sum of both token's maxed out values. Slope must be 0 as it's already maxed out.
        // `start` should stay the same and current timestamp updated.
        // 3. total supply at current time must be sum of both token's maxed out values.
        // 4. total supply at currentTime and `currentTime + X` must be the same(sum of maxed out values of both tokens)
        // 5. last global point must have slope 0 and bias as sum of both token's maxed out values.
        // 6. Since `to`'s end is greater than `from`'s end, and we make `from` to become 0, `to`'s slope change must also include `to`'s slope.
        uint256 from = escrow.createLock(Lock_1_Amount);
        (uint256 fromLockWeekStart, uint256 fromLockEnd, uint256 fromLockCurrentTime) = getTimes();

        vm.warp(block.timestamp + checkpointInterval);
        uint256 to = escrow.createLock(Lock_2_Amount);
        (uint256 toLockWeekStart, uint256 toLockEnd, uint256 toLockCurrentTime) = getTimes();

        // we merge after both are mature.
        vm.warp(toLockEnd + 1 hours);
        escrow.merge(from, to);

        uint256 currentTs = block.timestamp;

        // 1
        {
            uint256 fromLatestEpoch = curve.tokenPointLatestIndex(from);
            assertEq(fromLatestEpoch, 2);

            TokenPoint memory fromP = curve.tokenPointHistory(from, fromLatestEpoch);

            assertEq(fromP.coefficients[0], 0);
            assertEq(fromP.coefficients[1], 0);
            // assertEq(fromP.start, weekStartTs); TODO: check it on `locked()`
            assertEq(fromP.ts, currentTs);
        }

        int256 currentTotalBiasFP = biasFP(Lock_1_Amount, fromLockEnd - fromLockWeekStart) +
            biasFP(Lock_2_Amount, toLockEnd - toLockWeekStart);

        // 2
        {
            uint256 toLatestEpoch = curve.tokenPointLatestIndex(to);
            assertEq(toLatestEpoch, 2);

            TokenPoint memory toP = curve.tokenPointHistory(to, toLatestEpoch);

            assertEq(toP.coefficients[0], currentTotalBiasFP);
            assertEq(toP.coefficients[1], 0);
            // assertEq(toP.start, weekStartTs); TODO: check it on `locked()`
            assertEq(toP.ts, currentTs);
        }

        // 3, 4
        assertTotalSupply(currentTs - 1, currentTotalBiasFP);
        assertTotalSupply(currentTs, currentTotalBiasFP);
        assertTotalSupply(currentTs + 1, currentTotalBiasFP);

        // 5
        GlobalPoint memory lastPoint = curve.globalPointHistory(curve.globalPointLatestIndex());

        assertEq(lastPoint.slope, 0);
        assertEq(lastPoint.bias, currentTotalBiasFP);
        assertEq(lastPoint.ts, currentTs);
        // assertEq(lastPoint.start, (currentTs / checkpointInterval) * checkpointInterval); // TODO:GIORGI on the global points, we also store something like lastPoint.start = _newLocked.start
        // in this specific scenario, lastPoint.start becomes the `to` token's start which is in the past. does this make sense at all ?

        // 6
        assertEq(curve.slopeChanges(fromLockEnd), slopeFP(Lock_1_Amount));
        assertEq(curve.slopeChanges(toLockEnd), slopeFP(Lock_2_Amount));
    }

    // ====================SPLIT TESTS==========================
    function test_Split_shouldRevert_IfSenderIsNotApprovedOrOwner() public {
        uint256 from = escrow.createLock(Lock_1_Amount);

        vm.startPrank(address(999));
        vm.expectRevert(IVotingEscrowCoreErrors.NotApprovedOrOwner.selector);
        escrow.split(from, 10);
    }

    function test_Split_shouldRevert_ifAmountZero() public {
        uint256 from = escrow.createLock(Lock_1_Amount);

        vm.expectRevert(IVotingEscrowCoreErrors.ZeroAmount.selector);
        escrow.split(from, 0);
    }

    function test_Split_shouldRevert_ifAmountTooBig() public {
        uint256 from = escrow.createLock(Lock_1_Amount);

        vm.expectRevert(ISplit.SplitAmountTooBig.selector);
        escrow.split(from, Lock_1_Amount);
    }

    function test_Split_TokenNotMature() public {
        // 1. the tokenId's point must become 0
        // 2. we should have 2 new tokenIds with `value` and `Lock_1_Amount - value` with their according bias and slope.
        // 3. total supply at current timestamp must be both of the token's bias summed up till that point.
        // 4. check that after the original token's end, the total supply doesn't increase.
        // 5. slope changes must still include the original token's slope at the same original end.
        uint256 value = 20e18;
        uint256 tokenId = escrow.createLock(Lock_1_Amount);
        (uint256 weekStartTs, uint256 endTs, ) = getTimes();

        // Still warp just to ensure that we changed the current timestamp
        // but not wrap after the end.
        vm.warp(block.timestamp + checkpointInterval);

        // TODO:GIORGI
        // vm.expectEmit();
        // emit ISplit.Split(tokenId, 2, 3, sender, Lock_1_Amount - value, value);

        escrow.split(tokenId, value);   
        uint256 currentTs = block.timestamp;

        int256 slope1 = slopeFP(Lock_1_Amount - value);
        int256 slope2 = slopeFP(value);

        // 1
        uint256 mainTokenIdEpoch = curve.tokenPointLatestIndex(tokenId);
        assertEq(mainTokenIdEpoch, 2);

        TokenPoint memory mainP = curve.tokenPointHistory(tokenId, mainTokenIdEpoch);

        assertEq(mainP.coefficients[0], 0);
        assertEq(mainP.coefficients[1], 0);
        // assertEq(mainP.start, weekStartTs); TODO: check it on `locked()`
        assertEq(mainP.ts, block.timestamp);

        // 2
        {
            uint256 token1Epoch = curve.tokenPointLatestIndex(2);
            assertEq(token1Epoch, 1);
            TokenPoint memory token1P = curve.tokenPointHistory(
                2, // tokenId
                token1Epoch
            );

            assertEq(
                token1P.coefficients[0],
                biasFP(Lock_1_Amount - value, block.timestamp - weekStartTs)
            );
            assertEq(token1P.coefficients[1], slope1);
            // assertEq(token1P.start, weekStartTs); TODO: check it on `locked()`
            assertEq(token1P.ts, block.timestamp);

            uint256 token2Epoch = curve.tokenPointLatestIndex(3);
            assertEq(token2Epoch, 1);
            TokenPoint memory token2P = curve.tokenPointHistory(
                3, // tokenId
                token2Epoch
            );

            assertEq(token2P.coefficients[0], biasFP(value, block.timestamp - weekStartTs));
            assertEq(token2P.coefficients[1], slope2);
            // assertEq(token2P.start, weekStartTs); TODO: check it on `locked()`
            assertEq(token2P.ts, block.timestamp);
        }

        // 3.
        assertTotalSupply(
            currentTs,
            biasFP(Lock_1_Amount - value, currentTs - weekStartTs) +
                biasFP(value, currentTs - weekStartTs)
        );

        assertTotalSupply(currentTs, biasFP(Lock_1_Amount, currentTs - weekStartTs));

        // 4.
        assertTotalSupply(
            endTs,
            biasFP(Lock_1_Amount - value, endTs - weekStartTs) + biasFP(value, endTs - weekStartTs)
        );
        assertTotalSupply(endTs, biasFP(Lock_1_Amount, endTs - weekStartTs));

        assertTotalSupply(
            endTs + 5,
            biasFP(Lock_1_Amount - value, endTs - weekStartTs) + biasFP(value, endTs - weekStartTs)
        );

        // 5
        assertEq(curve.slopeChanges(endTs), slope1 + slope2);
    }

    function test_Split_TokenAlreadyMature() public {
        // 1. TotalSupply before and after the split must not change.
        // 2. the tokenId's point must become 0
        // 3. we should have 2 new tokenIds with `value` and `Lock_1_Amount - value` with their according bias and slope.
        // 4. total supply at current timestamp must be both of the token's max-out biases summed up.
        // 5. slope changes must still include the original token's slope at the same original end.
        uint256 value = 20e18;
        uint256 tokenId = escrow.createLock(Lock_1_Amount);
        (uint256 weekStartTs, uint256 endTs, ) = getTimes();

        // warp after the token end so it's mature.
        vm.warp(endTs + 1 hours);

        // 1
        assertTotalSupply(block.timestamp, biasFP(Lock_1_Amount, endTs - weekStartTs));
        escrow.split(tokenId, value);
        assertTotalSupply(block.timestamp, biasFP(Lock_1_Amount, endTs - weekStartTs));

        uint256 currentTs = block.timestamp;

        // 2
        uint256 mainTokenIdEpoch = curve.tokenPointLatestIndex(tokenId);
        assertEq(mainTokenIdEpoch, 2);

        TokenPoint memory mainP = curve.tokenPointHistory(tokenId, mainTokenIdEpoch);

        assertEq(mainP.coefficients[0], 0);
        assertEq(mainP.coefficients[1], 0);
        // assertEq(mainP.start, weekStartTs); TODO: check it on `locked()`
        assertEq(mainP.ts, block.timestamp);

        // 2
        {
            uint256 token1Epoch = curve.tokenPointLatestIndex(2);
            assertEq(token1Epoch, 1);
            TokenPoint memory token1P = curve.tokenPointHistory(
                2, // tokenId
                token1Epoch
            );

            assertEq(token1P.coefficients[0], biasFP(Lock_1_Amount - value, endTs - weekStartTs));
            assertEq(token1P.coefficients[1], 0);
            // assertEq(token1P.start, weekStartTs); TODO: check it on `locked()`
            assertEq(token1P.ts, block.timestamp);

            uint256 token2Epoch = curve.tokenPointLatestIndex(3);
            assertEq(token2Epoch, 1);
            TokenPoint memory token2P = curve.tokenPointHistory(
                3, // tokenId
                token2Epoch
            );

            assertEq(token2P.coefficients[0], biasFP(value, endTs - weekStartTs));
            assertEq(token2P.coefficients[1], 0);
            // assertEq(token2P.start, weekStartTs); TODO: check it on `locked()`
            assertEq(token2P.ts, block.timestamp);
        }

        // 3.
        assertTotalSupply(
            currentTs,
            biasFP(Lock_1_Amount - value, endTs - weekStartTs) + biasFP(value, endTs - weekStartTs)
        );

        assertTotalSupply(currentTs, biasFP(Lock_1_Amount, endTs - weekStartTs));

        // 4.
        assertTotalSupply(
            endTs,
            biasFP(Lock_1_Amount - value, endTs - weekStartTs) + biasFP(value, endTs - weekStartTs)
        );
        assertTotalSupply(endTs, biasFP(Lock_1_Amount, endTs - weekStartTs));

        assertTotalSupply(
            endTs + 5,
            biasFP(Lock_1_Amount - value, endTs - weekStartTs) + biasFP(value, endTs - weekStartTs)
        );

        // 5
        assertEq(curve.slopeChanges(endTs), slopeFP(Lock_1_Amount));
    }

    function test_multipleMergeAndSplit(uint208[10] memory _amounts) public {
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < _amounts.length; i++) {
            _amounts[i] = uint208(bound(_amounts[i], 1, 1000));
            _amounts[i] *= 1e18;

            totalAmount += _amounts[i];
        }

        // will produce from tokenId = 1 to tokenId = amounts.length
        for (uint256 i = 0; i < _amounts.length; i++) {
            escrow.createLock(_amounts[i]);
        }

        vm.warp(block.timestamp + 1 hours);

        uint256 totalSupplyBefore = curve.supplyAt(block.timestamp);

        // merge 1 into 2, 3 into 4, 5 into 6, 7 into 8, 9 into 10
        for (uint256 i = 0; i < _amounts.length; i += 2) {
            escrow.merge(i + 1, i + 2);
        }

        // split 2, 4, 6, 8
        for (uint256 i = 2; i < _amounts.length; i += 2) {
            escrow.split(i, (_amounts[i - 1] * 30) / 100);
        }

        uint256 totalSupplyAfter = curve.supplyAt(block.timestamp);
        assertEq(totalSupplyBefore, totalSupplyAfter);

        // TODO: we need to check deviations.
    }

    // ======= Deviation Tests =========

    function testFuzz_global(uint208[10] memory amounts, uint256 currentTs) public {
        for (uint256 i = 0; i < amounts.length; i++) {
            vm.assume(amounts[i] <= 1e20);
            vm.assume(amounts[i] != 0);
        }

        uint256 amount = 2049e18;
        uint256 splitValue = 892e18;

        uint256 tokenId = escrow.createLock(amount);

        uint256 depositWeekTs = (block.timestamp / checkpointInterval) * checkpointInterval;

        uint256 timestampAt = depositWeekTs + maxTime - 1;

        uint256 beforeSupply = curve.supplyAt(timestampAt);

        int256 beforeSupplyFP = biasFP(amount, timestampAt - depositWeekTs);

        escrow.split(tokenId, splitValue);

        int256 afterSupplyFP = biasFP(amount - splitValue, timestampAt - depositWeekTs) +
            biasFP(splitValue, timestampAt - depositWeekTs);

        // console.log(beforeSupplyFP - afterSupplyFP, timestampAt - depositWeekTs);
    }
}
