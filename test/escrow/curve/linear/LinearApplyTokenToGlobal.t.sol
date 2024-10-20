// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {console2 as console} from "forge-std/console2.sol";

import {LinearIncreasingEscrow, IVotingEscrow, IEscrowCurve} from "src/escrow/increasing/LinearIncreasingEscrow.sol";
import {IVotingEscrowIncreasing, ILockedBalanceIncreasing} from "src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol";

import {LinearCurveBase} from "./LinearBase.sol";

contract TestLinearIncreasingApplyTokenChange is LinearCurveBase {
    function _copyNewToOld(
        TokenPoint memory _new,
        TokenPoint memory _old
    ) internal pure returns (TokenPoint memory copied) {
        _old.coefficients[0] = _new.coefficients[0];
        _old.coefficients[1] = _new.coefficients[1];
        _old.writtenTs = _new.writtenTs;
        _old.checkpointTs = _new.checkpointTs;
        _old.bias = _new.bias;
        return _old;
    }

    // when run on an empty global point, adds the user's own point
    // deposit
    function testEmptyGlobalDeposit() public {
        vm.warp(100);
        GlobalPoint memory globalPoint;
        globalPoint.ts = block.timestamp;

        TokenPoint memory oldPoint;

        TokenPoint memory newPoint = curve.previewPoint(10 ether);
        newPoint.checkpointTs = uint128(block.timestamp);
        // write it

        globalPoint = curve.applyTokenUpdateToGlobal(0, oldPoint, newPoint, globalPoint);

        uint expectedBias = 10 ether;

        assertEq(uint(globalPoint.coefficients[0]) / 1e18, expectedBias);
        assertEq(globalPoint.ts, block.timestamp);
        assertEq(globalPoint.coefficients[1], newPoint.coefficients[1]);
    }

    // change - same block
    function testEmptyGlobalChangeSameBlock(uint128 _newBalance) public {
        vm.warp(100);
        GlobalPoint memory globalPoint;
        globalPoint.ts = block.timestamp;

        TokenPoint memory oldPoint;

        TokenPoint memory newPoint0 = curve.previewPoint(10 ether);
        newPoint0.checkpointTs = uint128(block.timestamp);
        globalPoint = curve.applyTokenUpdateToGlobal(0, oldPoint, newPoint0, globalPoint);

        // copy the new to old point and redefine the new point
        oldPoint = _copyNewToOld(newPoint0, oldPoint);

        TokenPoint memory newPoint1 = curve.previewPoint(_newBalance);
        newPoint1.checkpointTs = uint128(block.timestamp);

        GlobalPoint memory newGlobalPoint = curve.applyTokenUpdateToGlobal(
            0,
            oldPoint,
            newPoint1,
            globalPoint
        );

        assertEq(uint(newGlobalPoint.coefficients[0]) / 1e18, _newBalance);
        assertEq(newGlobalPoint.ts, block.timestamp);
        assertEq(newGlobalPoint.coefficients[1], newPoint1.coefficients[1]);
    }

    // when run on an existing global point, increments the global point
    // deposit
    function testDepositOnExistingGlobalState() public {
        vm.warp(100);

        GlobalPoint memory globalPoint;
        globalPoint.ts = block.timestamp;

        // imagine the state is set with 100 ether total
        globalPoint.coefficients[0] = curve.previewPoint(100 ether).coefficients[0];
        globalPoint.coefficients[1] = curve.previewPoint(100 ether).coefficients[1];

        TokenPoint memory oldPoint; // 0

        TokenPoint memory newPoint = curve.previewPoint(10 ether);
        newPoint.checkpointTs = uint128(block.timestamp);

        int cachedSlope = globalPoint.coefficients[1];

        globalPoint = curve.applyTokenUpdateToGlobal(0, oldPoint, newPoint, globalPoint);

        // expectation: bias && slope incremented
        assertEq(uint(globalPoint.coefficients[0]) / 1e18, 110 ether);
        assertEq(globalPoint.ts, block.timestamp);
        assertEq(globalPoint.coefficients[1], cachedSlope + newPoint.coefficients[1]);
    }

    // change - elapsed
    function testChangeOnExistingGlobalStateElapsedTime() public {
        vm.warp(100);

        GlobalPoint memory globalPoint;
        globalPoint.ts = block.timestamp;

        // imagine the state is set with 100 ether total
        globalPoint.coefficients[0] = curve.previewPoint(100 ether).coefficients[0];
        globalPoint.coefficients[1] = curve.previewPoint(100 ether).coefficients[1];

        TokenPoint memory oldPoint; // 0

        TokenPoint memory newPoint0 = curve.previewPoint(10 ether);
        newPoint0.checkpointTs = uint128(block.timestamp);

        globalPoint = curve.applyTokenUpdateToGlobal(0, oldPoint, newPoint0, globalPoint);
        int cachedCoeff0 = globalPoint.coefficients[0];

        // copy the new to old point and redefine the new point
        oldPoint = _copyNewToOld(newPoint0, oldPoint);

        vm.warp(200);

        TokenPoint memory newPoint1 = curve.previewPoint(20 ether);
        newPoint1.checkpointTs = uint128(block.timestamp);

        // define a new global point by evaluating it over the elapsed time
        globalPoint.coefficients[0] = curve.getBiasUnbound(100, globalPoint.coefficients);
        globalPoint.ts = block.timestamp;

        GlobalPoint memory newGlobalPoint = curve.applyTokenUpdateToGlobal(
            0,
            oldPoint,
            newPoint1,
            globalPoint
        );

        // we would now expect that the new global point is:
        // 110 ether evaled over 100 seconds - (10 ether evaled over 100 seconds) + (20 ether)
        uint expectedCoeff0 = curve.getBias(100, 110 ether) -
            curve.getBias(100, 10 ether) +
            20 ether;
        int expectedCoeff1 = globalPoint.coefficients[1] -
            newPoint0.coefficients[1] +
            newPoint1.coefficients[1];

        assertEq(uint(newGlobalPoint.coefficients[0]) / 1e18, uint(expectedCoeff0));
        assertEq(newGlobalPoint.ts, block.timestamp);
        assertEq(newGlobalPoint.coefficients[1], expectedCoeff1);
    }

    // decrease
    // exit

    // same block change
    // deposit
    // increase
    // decrease
    // exit

    // TODO a few extra tests here

    // change - future?

    // correctly maxes out based on the lockStart
}
