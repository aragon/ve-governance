pragma solidity ^0.8.17;

import {console2 as console} from "forge-std/console2.sol";

import {QuadraticIncreasingEscrow, IVotingEscrow, IEscrowCurve} from "src/escrow/increasing/QuadraticIncreasingEscrow.sol";
import {IVotingEscrowIncreasing, ILockedBalanceIncreasing} from "src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol";
import {VotingEscrow} from "src/escrow/increasing/VotingEscrowIncreasing.sol";
import {Lock} from "src/escrow/increasing/Lock.sol";

import {Test} from "forge-std/Test.sol";
import {SafeCastUpgradeable as SafeCast} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

import {CurveConstantLib} from "@libs/CurveConstantLib.sol";
import {Clock} from "../src/clock/Clock.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {ProxyLib} from "@libs/ProxyLib.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract TestEscrow is Test {
    using ProxyLib for address;
    using SafeCast for uint256;

    uint208 internal TOKEN_5K = 5e21;

    uint256 internal WEEK = 604800;
    uint256 internal DAY = 86400;

    QuadraticIncreasingEscrow internal curve;
    VotingEscrow internal escrow;
    Clock internal clock;

    uint208 internal Lock_1_Amount = 50e18;
    uint208 internal Lock_2_Amount = 30e18;

    uint256 internal Slope_1 = ((Lock_1_Amount * 1e18) / CurveConstantLib.MAX_TIME);
    uint256 internal Slope_2 = ((Lock_2_Amount * 1e18) / CurveConstantLib.MAX_TIME);

    uint256 internal Lock_1_ts;
    uint256 internal Lock_1_start;

    uint256 internal Lock_2_ts;
    uint256 internal Lock_2_start;

    address public sender = address(123);

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
        weekStartTs = (block.timestamp / WEEK) * WEEK;
        endTs = weekStartTs + CurveConstantLib.MAX_TIME;
        currentTs = block.timestamp;
    }

    function slopeFP(uint256 _amount) private pure returns (uint256) {
        return ((_amount * 1e18) / CurveConstantLib.MAX_TIME);
    }

    function biasFP(uint256 _amount, uint256 _duration) private pure returns (uint256) {
        return _amount * 1e18 + ((_amount * 1e18) / CurveConstantLib.MAX_TIME) * _duration;
    }

    function bias(uint256 _amount, uint256 _duration) private pure returns (uint256 bias_) {
        return biasFP(_amount, _duration) / 1e18;
    }

    function assertTotalSupply(uint256 _t, uint256 _amountFP) private view {
        assertEq(curve.supplyAt(_t), _amountFP / 1e18);
    }

    function setUp() public {
        DAO _dao = DAO(payable(new ERC1967Proxy(address(new DAO()), bytes(""))));
        _dao.initialize({
            _metadata: bytes(""),
            _initialOwner: address(this),
            _trustedForwarder: address(0),
            daoURI_: "ipfs://"
        });

        curve = new QuadraticIncreasingEscrow();
        clock = new Clock();
        address impl = address(new VotingEscrow());

        MockERC20 token = new MockERC20();

        escrow = VotingEscrow(
            impl.deployUUPSProxy(
                abi.encodeCall(
                    VotingEscrow.initialize,
                    (address(token), address(_dao), address(clock), 0)
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
        Lock_1_start = (block.timestamp / WEEK) / WEEK;
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
        assertEq(lock.start, (currentTs / WEEK) * WEEK);

        // 2
        assertEq(curve.latestPointIndex(), 1);
        assertEq(curve.userPointEpoch(1), 1);

        // 3
        QuadraticIncreasingEscrow.UserPoint memory p = curve.pointHistory(1);
        assertEq(p.ts, currentTs);
        assertEq(p.bias, biasFP(Lock_1_Amount, currentTs - weekStartTs));
        assertEq(p.start, weekStartTs);
        assertEq(p.slope, Slope_1);

        // 4,5,6
        assertTotalSupply(currentTs, biasFP(Lock_1_Amount, currentTs - weekStartTs));
        assertTotalSupply(currentTs - 1, 0);
        assertTotalSupply(endTs, biasFP(Lock_1_Amount, endTs - weekStartTs));
        assertTotalSupply(endTs + 10, biasFP(Lock_1_Amount, endTs - weekStartTs));

        // 7
        assertEq(curve.slopeChanges(endTs), Slope_1);

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
        assertEq(curve.latestPointIndex(), 2);
        assertEq(curve.userPointEpoch(1), 1);
        assertEq(curve.userPointEpoch(2), 1);

        // 2, 3
        QuadraticIncreasingEscrow.UserPoint memory p = curve.pointHistory(2);
        assertEq(p.ts, currentTs);
        assertEq(
            p.bias,
            biasFP(Lock_1_Amount, currentTs - weekStartTs) +
                biasFP(Lock_2_Amount, currentTs - weekStartTs)
        );

        assertEq(p.start, weekStartTs);
        assertEq(p.slope, Slope_1 + Slope_2);

        // 4, 5, 6
        assertTotalSupply(currentTs, biasFP(totalLockAmount, currentTs - weekStartTs));
        assertTotalSupply(currentTs - 1, 0);
        assertTotalSupply(endTs, biasFP(totalLockAmount, endTs - weekStartTs));
        assertTotalSupply(endTs + 10, biasFP(totalLockAmount, endTs - weekStartTs));

        // 7
        assertEq(curve.slopeChanges(endTs), Slope_1 + Slope_2);
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
        vm.warp(block.timestamp + WEEK);

        escrow.createLock(Lock_2_Amount);

        (uint256 weekStartTs, uint256 endTs, uint256 currentTs) = getTimes();

        // 1
        // epoch is 3 because there's a week between the locks
        // which must be updated upon 2nd lock's insert.
        assertEq(curve.latestPointIndex(), 3);
        assertEq(curve.userPointEpoch(1), 1);
        assertEq(curve.userPointEpoch(2), 1);

        uint256 currentTotalBiasFP = biasFP(Lock_1_Amount, currentTs - Lock_1_start) +
            biasFP(Lock_2_Amount, currentTs - weekStartTs);

        // 2, 3
        QuadraticIncreasingEscrow.UserPoint memory p = curve.pointHistory(3);
        assertEq(p.ts, currentTs);
        assertEq(p.bias, currentTotalBiasFP);
        assertEq(p.start, weekStartTs);
        assertEq(p.slope, Slope_1 + Slope_2);

        // 4, 5
        assertTotalSupply(currentTs, currentTotalBiasFP);
        assertTotalSupply(currentTs - 1, biasFP(Lock_1_Amount, currentTs - 1 - Lock_1_start));

        uint256 Lock_1_end = Lock_1_start + CurveConstantLib.MAX_TIME;
        uint256 Lock_2_end = weekStartTs + CurveConstantLib.MAX_TIME;

        uint256 Lock_1_MAX = biasFP(Lock_1_Amount, Lock_1_end - Lock_1_start);
        uint256 LOCK_2_MAX = biasFP(Lock_2_Amount, Lock_2_end - weekStartTs);

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
        assertEq(curve.slopeChanges(Lock_1_end), Slope_1);
        assertEq(curve.slopeChanges(Lock_2_end), Slope_2);
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
        uint256 currentTime = block.timestamp + CurveConstantLib.MAX_TIME + 2 hours;
        vm.warp(currentTime);

        escrow.createLock(Lock_2_Amount);

        (uint256 weekStartTs, uint256 endTs, uint256 currentTs) = getTimes();

        // Calculate how many weeks between our locks + 2 as last lock's record and new lock's record.
        uint256 lastEpoch = (currentTime - Lock_1_start) / WEEK + 2;

        uint256 Lock_1_end = Lock_1_start + CurveConstantLib.MAX_TIME;
        uint256 Lock_2_end = weekStartTs + CurveConstantLib.MAX_TIME;

        // 1
        // epoch is `howManyWeeksBetween + 2`. We add 2 because the first lock and last lock.
        assertEq(curve.latestPointIndex(), lastEpoch);
        assertEq(curve.userPointEpoch(1), 1);
        assertEq(curve.userPointEpoch(2), 1);

        uint256 currentTotalBiasFP = biasFP(Lock_1_Amount, Lock_1_end - Lock_1_start) +
            biasFP(Lock_2_Amount, currentTs - weekStartTs);

        // 2, 3
        QuadraticIncreasingEscrow.UserPoint memory p = curve.pointHistory(lastEpoch);
        assertEq(p.ts, currentTs);
        assertEq(p.bias, currentTotalBiasFP);
        assertEq(p.start, weekStartTs);
        assertEq(p.slope, Slope_2);

        uint256 Lock_1_MAX = biasFP(Lock_1_Amount, Lock_1_end - Lock_1_start);
        uint256 Lock_2_MAX = biasFP(Lock_2_Amount, Lock_2_end - weekStartTs);

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
        assertEq(curve.slopeChanges(Lock_1_end), Slope_1);
        assertEq(curve.slopeChanges(Lock_2_end), Slope_2);
    }

    // ================== MERGE ============================
    function test_shouldRevert_IfNotMatureAndDifferentStart() public {
        uint256 from = escrow.createLock(Lock_1_Amount);

        // Warp so start dates end up different..
        vm.warp(block.timestamp + WEEK);
        uint256 to = escrow.createLock(Lock_2_Amount);

        vm.expectRevert(); //reverts as start dates are different and tokens are not mature.
        escrow.merge(from, to);
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

        escrow.merge(from, to);

        uint256 fromLatestEpoch = curve.userPointEpoch(from);
        assertEq(fromLatestEpoch, 1);

        // 1
        QuadraticIncreasingEscrow.UserPoint memory fromP = curve.userPointHistory_1(
            from,
            fromLatestEpoch
        );

        assertEq(fromP.bias, 0);
        assertEq(fromP.slope, 0);
        assertEq(fromP.start, weekStartTs);
        assertEq(fromP.ts, currentTs);

        // 2
        // since merge occured in the same block as `createLock`,
        // it should not cause extra epoch for user.
        uint256 toLatestEpoch = curve.userPointEpoch(to);
        assertEq(toLatestEpoch, 1);

        QuadraticIncreasingEscrow.UserPoint memory toP = curve.userPointHistory_1(
            to,
            toLatestEpoch
        );

        uint256 currentTotalBiasFP = biasFP(Lock_1_Amount, currentTs - weekStartTs) +
            biasFP(Lock_2_Amount, currentTs - weekStartTs);

        assertEq(toP.bias, currentTotalBiasFP);
        assertEq(toP.slope, Slope_1 + Slope_2);
        assertEq(toP.start, weekStartTs);
        assertEq(toP.ts, currentTs);

        uint256 end = weekStartTs + CurveConstantLib.MAX_TIME;
        uint256 LOCK_1_MAX = biasFP(Lock_1_Amount, end - weekStartTs);
        uint256 LOCK_2_MAX = biasFP(Lock_2_Amount, end - weekStartTs);

        // 3
        assertTotalSupply(currentTs, currentTotalBiasFP);

        // 4
        assertTotalSupply(currentTs + 10, currentTotalBiasFP + Slope_1 * 10 + Slope_2 * 10);

        // 5
        assertTotalSupply(end, LOCK_1_MAX + LOCK_2_MAX);
        assertTotalSupply(end + 10, LOCK_1_MAX + LOCK_2_MAX);

        // 6
        assertEq(curve.slopeChanges(end), Slope_1 + Slope_2);
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

        uint256 end = weekStartTs + CurveConstantLib.MAX_TIME;
        uint256 LOCK_1_MAX = biasFP(Lock_1_Amount, end - weekStartTs);
        uint256 LOCK_2_MAX = biasFP(Lock_2_Amount, end - weekStartTs);

        vm.warp(end + 1 hours);
        escrow.merge(from, to);

        uint256 currentTs = block.timestamp;

        uint256 fromLatestEpoch = curve.userPointEpoch(from);
        assertEq(fromLatestEpoch, 2);

        // 1
        QuadraticIncreasingEscrow.UserPoint memory fromP = curve.userPointHistory_1(
            from,
            fromLatestEpoch
        );

        assertEq(fromP.bias, 0);
        assertEq(fromP.slope, 0);
        assertEq(fromP.start, weekStartTs);
        assertEq(fromP.ts, currentTs);

        // 2
        // since merge occured in the different block than `createLock`,
        // it should  cause extra epoch for user.
        uint256 toLatestEpoch = curve.userPointEpoch(to);
        assertEq(toLatestEpoch, 2);

        QuadraticIncreasingEscrow.UserPoint memory toP = curve.userPointHistory_1(
            to,
            toLatestEpoch
        );

        uint256 currentTotalBiasFP = LOCK_1_MAX + LOCK_2_MAX;

        assertEq(toP.bias, currentTotalBiasFP);
        assertEq(toP.slope, 0);
        assertEq(toP.start, weekStartTs);
        assertEq(toP.ts, currentTs);

        // 3, 4
        assertTotalSupply(currentTs - 1, currentTotalBiasFP);
        assertTotalSupply(currentTs, currentTotalBiasFP);
        assertTotalSupply(currentTs + 1, currentTotalBiasFP);

        // 5
        QuadraticIncreasingEscrow.UserPoint memory lastPoint = curve.pointHistory(
            curve.latestPointIndex()
        );

        assertEq(lastPoint.slope, 0);
        assertEq(lastPoint.bias, currentTotalBiasFP);
        assertEq(lastPoint.ts, currentTs);
        // assertEq(lastPoint.start, (currentTs / WEEK) * WEEK); // TODO:GIORGI on the global points, we also store something like lastPoint.start = _newLocked.start
        // in this specific scenario, lastPoint.start becomes the `to` token's start which is in the past. does this make sense at all ?

        // 6
        assertEq(curve.slopeChanges(end), Slope_1 + Slope_2);
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

        vm.warp(block.timestamp + WEEK);
        uint256 to = escrow.createLock(Lock_2_Amount);
        (uint256 toLockWeekStart, uint256 toLockEnd, uint256 toLockCurrentTime) = getTimes();

        // we merge after both are mature.
        vm.warp(toLockEnd + 1 hours);
        escrow.merge(from, to);

        uint256 currentTs = block.timestamp;

        // 1
        {
            uint256 fromLatestEpoch = curve.userPointEpoch(from);
            assertEq(fromLatestEpoch, 2);

            QuadraticIncreasingEscrow.UserPoint memory fromP = curve.userPointHistory_1(
                from,
                fromLatestEpoch
            );

            assertEq(fromP.bias, 0);
            assertEq(fromP.slope, 0);
            assertEq(fromP.start, fromLockWeekStart);
            assertEq(fromP.ts, currentTs);
        }

        uint256 currentTotalBiasFP = biasFP(Lock_1_Amount, fromLockEnd - fromLockWeekStart) +
            biasFP(Lock_2_Amount, toLockEnd - toLockWeekStart);

        // 2
        {
            uint256 toLatestEpoch = curve.userPointEpoch(to);
            assertEq(toLatestEpoch, 2);

            QuadraticIncreasingEscrow.UserPoint memory toP = curve.userPointHistory_1(
                to,
                toLatestEpoch
            );

            assertEq(toP.bias, currentTotalBiasFP);
            assertEq(toP.slope, 0);
            assertEq(toP.start, toLockWeekStart);
            assertEq(toP.ts, currentTs);
        }

        // 3, 4
        assertTotalSupply(currentTs - 1, currentTotalBiasFP);
        assertTotalSupply(currentTs, currentTotalBiasFP);
        assertTotalSupply(currentTs + 1, currentTotalBiasFP);

        // 5
        QuadraticIncreasingEscrow.UserPoint memory lastPoint = curve.pointHistory(
            curve.latestPointIndex()
        );

        assertEq(lastPoint.slope, 0);
        assertEq(lastPoint.bias, currentTotalBiasFP);
        assertEq(lastPoint.ts, currentTs);
        // assertEq(lastPoint.start, (currentTs / WEEK) * WEEK); // TODO:GIORGI on the global points, we also store something like lastPoint.start = _newLocked.start
        // in this specific scenario, lastPoint.start becomes the `to` token's start which is in the past. does this make sense at all ?

        // 6
        assertEq(curve.slopeChanges(fromLockEnd), Slope_1);
        assertEq(curve.slopeChanges(toLockEnd), Slope_2);
    }

    // ====================SPLIT TESTS==========================
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
        vm.warp(block.timestamp + WEEK);

        escrow.split(tokenId, value);
        uint256 currentTs = block.timestamp;

        uint256 slope1 = slopeFP(Lock_1_Amount - value);
        uint256 slope2 = slopeFP(value);

        // 1
        uint256 mainTokenIdEpoch = curve.userPointEpoch(tokenId);
        assertEq(mainTokenIdEpoch, 2);

        QuadraticIncreasingEscrow.UserPoint memory mainP = curve.userPointHistory_1(
            tokenId,
            mainTokenIdEpoch
        );

        assertEq(mainP.bias, 0);
        assertEq(mainP.slope, 0);
        assertEq(mainP.start, weekStartTs);
        assertEq(mainP.ts, block.timestamp);

        // 2
        {
            uint256 token1Epoch = curve.userPointEpoch(2);
            assertEq(token1Epoch, 1);
            QuadraticIncreasingEscrow.UserPoint memory token1P = curve.userPointHistory_1(
                2, // tokenId
                token1Epoch
            );

            assertEq(token1P.bias, biasFP(Lock_1_Amount - value, block.timestamp - weekStartTs));
            assertEq(token1P.slope, slope1);
            assertEq(token1P.start, weekStartTs);
            assertEq(token1P.ts, block.timestamp);

            uint256 token2Epoch = curve.userPointEpoch(3);
            assertEq(token2Epoch, 1);
            QuadraticIncreasingEscrow.UserPoint memory token2P = curve.userPointHistory_1(
                3, // tokenId
                token2Epoch
            );

            assertEq(token2P.bias, biasFP(value, block.timestamp - weekStartTs));
            assertEq(token2P.slope, slope2);
            assertEq(token2P.start, weekStartTs);
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

    // ====================SPLIT TESTS==========================
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
        uint256 mainTokenIdEpoch = curve.userPointEpoch(tokenId);
        assertEq(mainTokenIdEpoch, 2);

        QuadraticIncreasingEscrow.UserPoint memory mainP = curve.userPointHistory_1(
            tokenId,
            mainTokenIdEpoch
        );

        assertEq(mainP.bias, 0);
        assertEq(mainP.slope, 0);
        assertEq(mainP.start, weekStartTs);
        assertEq(mainP.ts, block.timestamp);

        // 2
        {
            uint256 token1Epoch = curve.userPointEpoch(2);
            assertEq(token1Epoch, 1);
            QuadraticIncreasingEscrow.UserPoint memory token1P = curve.userPointHistory_1(
                2, // tokenId
                token1Epoch
            );

            assertEq(token1P.bias, biasFP(Lock_1_Amount - value, endTs - weekStartTs));
            assertEq(token1P.slope, 0);
            assertEq(token1P.start, weekStartTs);
            assertEq(token1P.ts, block.timestamp);

            uint256 token2Epoch = curve.userPointEpoch(3);
            assertEq(token2Epoch, 1);
            QuadraticIncreasingEscrow.UserPoint memory token2P = curve.userPointHistory_1(
                3, // tokenId
                token2Epoch
            );

            assertEq(token2P.bias, biasFP(value, endTs - weekStartTs));
            assertEq(token2P.slope, 0);
            assertEq(token2P.start, weekStartTs);
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
    
    
    // ======= Deviation Tests =========

    function testFuzz_global(uint208[10] memory amounts, uint256 currentTs) public {
        for (uint256 i = 0; i < amounts.length; i++) {
            vm.assume(amounts[i] <= 1e20);
            vm.assume(amounts[i] != 0);
        }

        uint256 amount = 2049e18;
        uint256 splitValue = 892e18;

        uint256 tokenId = escrow.createLock(amount);

        uint256 depositWeekTs = (block.timestamp / WEEK) * WEEK;

        uint256 timestampAt = depositWeekTs + CurveConstantLib.MAX_TIME - 1;

        uint256 beforeSupply = curve.supplyAt(timestampAt);

        uint256 beforeSupplyFP = biasFP(amount, timestampAt - depositWeekTs);

        escrow.split(tokenId, splitValue);

        uint256 afterSupplyFP = biasFP(amount - splitValue, timestampAt - depositWeekTs) +
            biasFP(splitValue, timestampAt - depositWeekTs);

        console.log(beforeSupplyFP - afterSupplyFP, timestampAt - depositWeekTs);
    }
}
