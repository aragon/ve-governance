// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {console2 as console} from "forge-std/console2.sol";

import {LinearIncreasingEscrow, IVotingEscrow, IEscrowCurve} from "src/escrow/increasing/LinearIncreasingEscrow.sol";
import {IVotingEscrowIncreasing, ILockedBalanceIncreasing} from "src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol";

import {LinearCurveBase} from "./LinearBase.sol";

contract TestLinearIncreasingScheduleChanges is LinearCurveBase {
    // setup function - initialize the curve

    // in testing this function we need to primarily focus on aggregating balances atop of
    // a predefined point, the unhappy path here is that there's some imbalance between what the lock is
    // saying and what the token point is saying.
    // for now, let's assume the happy path then think about sad paths

    function setUp() public override {
        super.setUp();
        //
    }

    // testing with no prior state
    function testFuzz_noPriorLockSchedulesIncrease(
        LockedBalance memory _newLocked,
        TokenPoint memory _newPoint,
        uint128[3] memory _boundCoeff
    ) public {
        vm.warp(0);
        // bound new lock start to uint32
        vm.assume(_newLocked.start < type(uint32).max);

        // other tests can check on the boundary
        vm.assume(_newLocked.start > 0);

        TokenPoint memory oldPoint;
        LockedBalance memory oldLocked;

        // bound coefficients - int128 to avoid overflow
        _newPoint.coefficients[0] = int(int128(_boundCoeff[0]));
        _newPoint.coefficients[1] = int(int128(_boundCoeff[1]));

        // write it
        curve.scheduleCurveChanges(oldPoint, _newPoint, oldLocked, _newLocked);

        // check the schedule
        int256[3] memory startChanges = curve.scheduledCurveChanges(_newLocked.start);
        int256[3] memory endChanges = curve.scheduledCurveChanges(
            _newLocked.start + curve.maxTime()
        );

        // start should be the same as the new point
        assertEq(
            startChanges[0],
            _newPoint.coefficients[0] / 1e18,
            "startChanges[0] != _newPoint.coefficients[0]"
        );
        assertEq(
            startChanges[1],
            _newPoint.coefficients[1] / 1e18,
            "startChanges[1] != _newPoint.coefficients[1]"
        );

        // end should be the same as the new point slope but in the negative
        assertEq(
            endChanges[1],
            -_newPoint.coefficients[1] / 1e18,
            "endChanges[1] != -_newPoint.coefficients[1]"
        );
    }

    // unrelated lock should be purely addive
    function testNoPriorLockLeavesExistingStateAlone() public {
        // write some existing state to some location
        uint48 start = 100;
        uint48 end = start + curve.maxTime();
        int256[3] memory startChanges = [int(1e18), int(2e18), int(0)];

        curve.writeSchedule(start, [startChanges[0], startChanges[1], 0]);
        curve.writeSchedule(end, [int(4e18), int(5e18), int(6e18)]);

        TokenPoint memory newPoint;
        TokenPoint memory oldPoint;

        LockedBalance memory newLocked = LockedBalance({start: start, amount: 100});

        newPoint.coefficients[0] = 1e18;
        newPoint.coefficients[1] = 2e18;

        oldPoint.coefficients[0] = startChanges[0];
        oldPoint.coefficients[1] = startChanges[1];

        curve.scheduleCurveChanges(
            oldPoint,
            newPoint,
            LockedBalance({start: 0, amount: 0}),
            newLocked
        );

        // expected - the old schedule is added to
        assertEq(curve.scheduledCurveChanges(start)[0], 2, "start[0] != 2");
        assertEq(curve.scheduledCurveChanges(start)[1], 4, "start[1] != 4");

        // 4 - 0 then 5 - 2
        assertEq(curve.scheduledCurveChanges(end)[0], 4, "end[0] != 4");
        assertEq(curve.scheduledCurveChanges(end)[1], 3, "end[1] != 3");
    }

    // if updating the user's own lock then we relace the relevant state
    function testUpdateState() public {
        // write some existing state to some location
        uint48 start = 100;
        uint48 end = start + curve.maxTime();

        int256[3] memory startChanges = [int(1e18), int(2e18), 0];

        curve.writeSchedule(start, [startChanges[0], startChanges[1], 0]);
        curve.writeSchedule(end, [int(4e18), int(5e18), 0]);

        TokenPoint memory newPoint;
        TokenPoint memory oldPoint;

        LockedBalance memory newLocked = LockedBalance({start: start, amount: 100});

        newPoint.coefficients[0] = 10e18;
        newPoint.coefficients[1] = 20e18;

        oldPoint.coefficients[0] = startChanges[0];
        oldPoint.coefficients[1] = startChanges[1];

        curve.scheduleCurveChanges(
            oldPoint,
            newPoint,
            LockedBalance({start: start, amount: 1}),
            newLocked
        );

        // expected - the old schedule is replaced
        assertEq(curve.scheduledCurveChanges(start)[0], 10, "start[0] != 10");
        assertEq(curve.scheduledCurveChanges(start)[1], 20, "start[1] != 20");

        // reset the old point leaving just the diff -
        // this will be 5 (original write) + 2 (the slope we are addng back) - 20 (new slope we remove)
        assertEq(curve.scheduledCurveChanges(end)[0], 4, "end[0] != 4");
        assertEq(curve.scheduledCurveChanges(end)[1], 5 + 2 - 20, "end[1] != -13"); //
    }

    // test an increasing write
    // we write some initial state then a first deposit then test an increase at 3 timestamps
    // => before start
    // => during the lock
    // => after finishing
    function _initState(
        uint48 start,
        int256[3] memory startCoeff
    )
        internal
        returns (
            TokenPoint memory oldPoint,
            TokenPoint memory newPoint,
            LockedBalance memory oldLocked,
            LockedBalance memory newLocked
        )
    {
        // write the first schedule change

        // set the first new locked w. start date
        newLocked = LockedBalance({start: start, amount: 1});

        // add to the new point for the first deposit
        newPoint.coefficients[0] = startCoeff[0];
        newPoint.coefficients[1] = startCoeff[1];

        // write the first schedule change
        curve.scheduleCurveChanges(oldPoint, newPoint, oldLocked, newLocked);

        // the old point should be the same as the new point
        oldPoint.coefficients[0] = newPoint.coefficients[0];
        oldPoint.coefficients[1] = newPoint.coefficients[1];

        oldLocked.start = newLocked.start;
        oldLocked.amount = newLocked.amount;

        // now setup the new new point
        newPoint.coefficients[0] = 10e18;
        newPoint.coefficients[1] = 20e18;

        // setup the new start
        newLocked = LockedBalance({start: start, amount: 2});
    }

    function _initStateAdd(
        uint48 start,
        int256[3] memory startCoeff
    )
        internal
        returns (
            TokenPoint memory oldPoint,
            TokenPoint memory newPoint,
            LockedBalance memory oldLocked,
            LockedBalance memory newLocked
        )
    {
        (oldPoint, newPoint, oldLocked, newLocked) = _initState(start, startCoeff);

        TokenPoint memory unrelatedPoint;

        unrelatedPoint.coefficients[0] = startCoeff[0];
        unrelatedPoint.coefficients[1] = startCoeff[1];
        // also write an unrelated point - this is someone else's lock
        curve.scheduleCurveChanges(
            oldPoint,
            unrelatedPoint,
            LockedBalance({start: 0, amount: 0}),
            LockedBalance({start: start, amount: 1})
        );
    }

    function testRewrite_startSameBeforeStart() public {
        uint48 start = 100;
        uint48 end = start + curve.maxTime();
        int256[3] memory startCoeff = [int(1e18), int(2e18), 0];
        (
            TokenPoint memory oldPoint,
            TokenPoint memory newPoint,
            LockedBalance memory oldLocked,
            LockedBalance memory newLocked
        ) = _initState(start, startCoeff);

        // write the second schedule change
        curve.scheduleCurveChanges(oldPoint, newPoint, oldLocked, newLocked);

        // expectation: we should have rewritten history completely
        assertEq(curve.scheduledCurveChanges(start)[0], 10, "start[0] != 10");
        assertEq(curve.scheduledCurveChanges(start)[1], 20, "start[1] != 20");

        // the end should be the same as the start but in the negative
        assertEq(curve.scheduledCurveChanges(end)[0], 0, "end[0] != 0");
        assertEq(curve.scheduledCurveChanges(end)[1], -20, "end[1] != -20");
    }

    function testRewrite_startSameAtStart(bool _exact) public {
        uint48 start = 100;
        uint48 end = start + curve.maxTime();
        int256[3] memory startCoeff = [int(1e18), int(2e18), 0];
        (
            TokenPoint memory oldPoint,
            TokenPoint memory newPoint,
            LockedBalance memory oldLocked,
            LockedBalance memory newLocked
        ) = _initState(start, startCoeff);

        vm.warp(_exact ? start : end - 1);
        // write the second schedule change
        curve.scheduleCurveChanges(oldPoint, newPoint, oldLocked, newLocked);

        // expectation, the window should have passed to schedule changes so instead we simply adjust the end
        assertEq(
            curve.scheduledCurveChanges(start)[0],
            startCoeff[0] / 1e18,
            "start[0] != startCoeff[0]"
        );
        assertEq(
            curve.scheduledCurveChanges(start)[1],
            startCoeff[1] / 1e18,
            "start[1] != startCoeff[1]"
        );

        // end should be the negative of the new point
        assertEq(curve.scheduledCurveChanges(end)[0], 0, "end[0] != 0");
        assertEq(curve.scheduledCurveChanges(end)[1], -20, "end[1] != -20");
    }

    function testRewrite_startSameAtEnd(bool _exact) public {
        uint48 start = 100;
        uint48 end = start + curve.maxTime();
        int256[3] memory startCoeff = [int(1e18), int(2e18), 0];
        (
            TokenPoint memory oldPoint,
            TokenPoint memory newPoint,
            LockedBalance memory oldLocked,
            LockedBalance memory newLocked
        ) = _initState(start, startCoeff);

        vm.warp(_exact ? end : end + 1);
        // write the second schedule change
        curve.scheduleCurveChanges(oldPoint, newPoint, oldLocked, newLocked);

        // expectation, window missed completely
        assertEq(
            curve.scheduledCurveChanges(start)[0],
            startCoeff[0] / 1e18,
            "start[0] != startCoeff[0]"
        );
        assertEq(
            curve.scheduledCurveChanges(start)[1],
            startCoeff[1] / 1e18,
            "start[1] != startCoeff[1]"
        );

        // end should be the negative of the new point
        assertEq(curve.scheduledCurveChanges(end)[0], 0, "end[0] != 0");
        assertEq(
            curve.scheduledCurveChanges(end)[1],
            -startCoeff[1] / 1e18,
            "end[1] != -startCoeff[1]"
        );
    }

    function testRewrite_diffStartBeforeStart() public {
        uint48 start = 100;
        uint48 end = start + curve.maxTime();
        int256[3] memory startCoeff = [int(1e18), int(2e18), 0];
        (
            TokenPoint memory oldPoint,
            TokenPoint memory newPoint,
            LockedBalance memory oldLocked,
            LockedBalance memory newLocked
        ) = _initState(start, startCoeff);

        // adjust the start date
        newLocked.start = start + 1;
        uint48 newEnd = end + 1;

        // write the second schedule change
        curve.scheduleCurveChanges(oldPoint, newPoint, oldLocked, newLocked);

        // expectation: the old lock has been removed at the start, replacing the new one
        assertEq(curve.scheduledCurveChanges(start)[0], 0, "start[0] != 0");
        assertEq(curve.scheduledCurveChanges(start)[1], 0, "start[1] != 0");
        assertEq(curve.scheduledCurveChanges(newLocked.start)[0], 10, "newLocked.start[0] != 10");
        assertEq(curve.scheduledCurveChanges(newLocked.start)[1], 20, "newLocked.start[1] != 20");

        // the end should be the same as the start but in the negative
        assertEq(curve.scheduledCurveChanges(end)[0], 0, "end[0] != 0");
        assertEq(curve.scheduledCurveChanges(end)[1], 0, "end[1] != 0");
        assertEq(curve.scheduledCurveChanges(newEnd)[0], 0, "newEnd[0] != 0");
        assertEq(curve.scheduledCurveChanges(newEnd)[1], -20, "newEnd[1] != -20");
    }

    function testRewrite_diffStartAtFirstStart(uint32 _warp) public {
        uint48 start = 100;
        vm.assume(_warp >= start);
        int256[3] memory startCoeff = [int(1e18), int(2e18), 0];
        (
            TokenPoint memory oldPoint,
            TokenPoint memory newPoint,
            LockedBalance memory oldLocked,
            LockedBalance memory newLocked
        ) = _initState(start, startCoeff);

        newLocked.start = start + 1;

        // assumption, there is no time period where this is allowed
        vm.warp(_warp);
        // write the second schedule change
        vm.expectRevert(RetroactiveStartChange.selector);
        curve.scheduleCurveChanges(oldPoint, newPoint, oldLocked, newLocked);
    }

    function testAdd_sameStartBeforeStart() public {
        uint48 start = 100;
        uint48 end = start + curve.maxTime();
        int256[3] memory startCoeff = [int(1e18), int(2e18), 0];
        (
            TokenPoint memory oldPoint,
            TokenPoint memory newPoint,
            LockedBalance memory oldLocked,
            LockedBalance memory newLocked
        ) = _initStateAdd(start, startCoeff);

        // write the second schedule change
        curve.scheduleCurveChanges(oldPoint, newPoint, oldLocked, newLocked);

        // expectation: the old lock has been removed at the start, replacing the new one
        // but the old point is still there
        assertEq(
            curve.scheduledCurveChanges(start)[0],
            (startCoeff[0] + newPoint.coefficients[0]) / 1e18,
            "start[0] != 11"
        );
        assertEq(
            curve.scheduledCurveChanges(start)[1],
            (startCoeff[1] + newPoint.coefficients[1]) / 1e18,
            "start[1] != 22"
        );

        // the end should be the aggregate of the first swapped point and the old point
        assertEq(curve.scheduledCurveChanges(end)[0], 0, "end[0] != 0");
        assertEq(
            curve.scheduledCurveChanges(end)[1],
            (-startCoeff[1] - newPoint.coefficients[1]) / 1e18,
            "end[1] != -22"
        );
    }

    function testAdd_sameStartAtStart(bool _exact) public {
        uint48 start = 100;
        uint48 end = start + curve.maxTime();
        int256[3] memory startCoeff = [int(1), int(2), 0];
        (
            TokenPoint memory oldPoint,
            TokenPoint memory newPoint,
            LockedBalance memory oldLocked,
            LockedBalance memory newLocked
        ) = _initStateAdd(start, startCoeff);

        vm.warp(_exact ? start : end - 1);
        // write the second schedule change
        curve.scheduleCurveChanges(oldPoint, newPoint, oldLocked, newLocked);

        // expected: both old points still there. end date is replaced for 1/2
        assertEq(
            curve.scheduledCurveChanges(start)[0],
            (startCoeff[0] + startCoeff[0]) / 1e18,
            "start[0] != 2"
        );
        assertEq(
            curve.scheduledCurveChanges(start)[1],
            (startCoeff[1] + startCoeff[1]) / 1e18,
            "start[1] != 4"
        );

        // the end should be the aggregate of the first swapped point and the old point
        assertEq(curve.scheduledCurveChanges(end)[0], 0, "end[0] != 0");
        assertEq(
            curve.scheduledCurveChanges(end)[1],
            (-startCoeff[1] - newPoint.coefficients[1]) / 1e18,
            "end[1] != -22"
        );
    }

    function testAdd_sameStartAtEnd(bool _exact) public {
        uint48 start = 100;
        uint48 end = start + curve.maxTime();
        int256[3] memory startCoeff = [int(1), int(2), 0];
        (
            TokenPoint memory oldPoint,
            TokenPoint memory newPoint,
            LockedBalance memory oldLocked,
            LockedBalance memory newLocked
        ) = _initStateAdd(start, startCoeff);

        vm.warp(_exact ? end : end + 1);
        // write the second schedule change
        curve.scheduleCurveChanges(oldPoint, newPoint, oldLocked, newLocked);

        // expected: nothing changes from the initial state
        assertEq(
            curve.scheduledCurveChanges(start)[0],
            (startCoeff[0] + startCoeff[0]) / 1e18,
            "start[0] != 2"
        );
        assertEq(
            curve.scheduledCurveChanges(start)[1],
            (startCoeff[1] + startCoeff[1]) / 1e18,
            "start[1] != 4"
        );

        assertEq(curve.scheduledCurveChanges(end)[0], 0, "end[0] != 0");
        assertEq(
            curve.scheduledCurveChanges(end)[1],
            (-startCoeff[1] - startCoeff[1]) / 1e18,
            "end[1] != -4"
        );
    }

    function testAdd_diffStartBeforeStart() public {
        uint48 start = 100;
        uint48 end = start + curve.maxTime();
        int256[3] memory startCoeff = [int(1), int(2), 0];
        (
            TokenPoint memory oldPoint,
            TokenPoint memory newPoint,
            LockedBalance memory oldLocked,
            LockedBalance memory newLocked
        ) = _initStateAdd(start, startCoeff);

        // adjust the start date
        newLocked.start = start + 1;

        // write the second schedule change
        curve.scheduleCurveChanges(oldPoint, newPoint, oldLocked, newLocked);

        // expectation: the old lock has been removed at the start and moved to the new start
        // but the old point is still there

        assertEq(curve.scheduledCurveChanges(start)[0], startCoeff[0] / 1e18, "start[0] != 1");
        assertEq(curve.scheduledCurveChanges(start)[1], startCoeff[1] / 1e18, "start[1] != 2");
        assertEq(
            curve.scheduledCurveChanges(newLocked.start)[0],
            newPoint.coefficients[0] / 1e18,
            "newLocked.start[0] != 10"
        );
        assertEq(
            curve.scheduledCurveChanges(newLocked.start)[1],
            newPoint.coefficients[1] / 1e18,
            "newLocked.start[1] != 20"
        );

        // the end should be the aggregate of the first swapped point and the old point
        assertEq(curve.scheduledCurveChanges(end)[0], 0, "end[0] != 0");
        assertEq(curve.scheduledCurveChanges(end)[1], -startCoeff[1] / 1e18, "end[1] != -2");
        assertEq(curve.scheduledCurveChanges(end + 1)[0], 0, "end[0] != 0");
        assertEq(
            curve.scheduledCurveChanges(end + 1)[1],
            -newPoint.coefficients[1] / 1e18,
            "end[1] != -20"
        );
    }

    // no reason to suspect otherwise but good to check reductions are well behaved
    function testReduction() public {
        uint48 start = 100;
        uint48 end = start + curve.maxTime();

        int256[3] memory startCoeff = [int(10e18), int(20e18), 0];
        (
            TokenPoint memory oldPoint,
            TokenPoint memory newPoint,
            LockedBalance memory oldLocked,
            LockedBalance memory newLocked
        ) = _initState(start, startCoeff);

        // rewrite our new point to be 1, 2
        newPoint.coefficients[0] = 1e18;
        newPoint.coefficients[1] = 2e18;

        // write the second schedule change
        curve.scheduleCurveChanges(oldPoint, newPoint, oldLocked, newLocked);

        // expectation: the old lock has been removed at the start, replacing the new one
        assertEq(curve.scheduledCurveChanges(start)[0], 1, "start[0] != 1");
        assertEq(curve.scheduledCurveChanges(start)[1], 2, "start[1] != 2");

        // the end should be the same as the start but in the negative
        assertEq(curve.scheduledCurveChanges(end)[0], 0, "end[0] != 0");
        assertEq(curve.scheduledCurveChanges(end)[1], -2, "end[1] != -2");
    }

    // TODO: unhappy path
    // both locked are zero
    // the old point and new point dont align with the locks
    // reverts if trying to decrease when there's nothing in the old lock or if new lock > old lock
    // has no impact if the deposits are the same (might revert)
}
