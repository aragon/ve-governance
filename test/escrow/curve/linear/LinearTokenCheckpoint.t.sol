// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {console2 as console} from "forge-std/console2.sol";

import {LinearIncreasingEscrow, IVotingEscrow, IEscrowCurve} from "src/escrow/increasing/LinearIncreasingEscrow.sol";
import {IVotingEscrowIncreasing, ILockedBalanceIncreasing} from "src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol";

import {LinearCurveBase} from "./LinearBase.sol";
contract TestLinearIncreasingCurveTokenCheckpoint is LinearCurveBase {
    function _setValidateState(
        uint256 _tokenId,
        LockedBalance memory _oldLocked,
        uint32 _warp
    ) internal {
        // Common fuzz assumptions
        vm.assume(_oldLocked.start > 0 && _tokenId > 0);
        vm.assume(_oldLocked.start >= _warp);
        vm.assume(_oldLocked.start < type(uint48).max);
        vm.assume(_oldLocked.amount <= 2 ** 127 - 1);
        vm.warp(_warp);

        // write the first point
        curve.tokenCheckpoint(_tokenId, LockedBalance(0, 0), _oldLocked);
    }

    function testFuzz_canWriteANewCheckpointWithCorrectParams(
        uint256 _tokenId,
        LockedBalance memory _newLocked,
        uint32 _warp
    ) public {
        vm.assume(_newLocked.start > 0 && _tokenId > 0);
        vm.warp(_warp);
        vm.assume(_newLocked.start >= _warp);
        // solmate not a fan of this
        vm.assume(_newLocked.amount <= 2 ** 127);

        (TokenPoint memory oldPoint, TokenPoint memory newPoint) = curve.tokenCheckpoint(
            _tokenId,
            LockedBalance(0, 0),
            _newLocked
        );

        // the old point should be zero zero
        assertEq(oldPoint.bias, 0);
        assertEq(oldPoint.checkpointTs, 0);
        assertEq(oldPoint.writtenTs, 0);
        assertEq(oldPoint.coefficients[0], 0);
        assertEq(oldPoint.coefficients[1], 0);

        // new point should have the correct values
        int256[3] memory coefficients = curve.getCoefficients(_newLocked.amount);

        assertEq(newPoint.bias, _newLocked.amount, "bias incorrect");
        assertEq(newPoint.checkpointTs, _newLocked.start, "checkpointTs incorrect");
        assertEq(newPoint.writtenTs, _warp, "writtenTs incorrect");
        assertEq(newPoint.coefficients[0] / 1e18, coefficients[0], "constant incorrect");
        assertEq(newPoint.coefficients[1] / 1e18, coefficients[1], "linear incorrect");

        // token interval == 1
        assertEq(curve.tokenPointIntervals(_tokenId), 1, "token interval incorrect");

        // token is recorded
        bytes32 tokenPointHash = keccak256(abi.encode(newPoint));
        bytes32 historyHash = keccak256(abi.encode(curve.tokenPointHistory(_tokenId, 1)));
        assertEq(tokenPointHash, historyHash, "token point not recorded correctly");
    }

    function testFuzz_case1_AmountSameStartSame(
        uint256 _tokenId,
        LockedBalance memory _oldLocked,
        uint32 _warp
    ) public {
        // Initialize state
        _setValidateState(_tokenId, _oldLocked, _warp);

        // Variables
        TokenPoint memory oldPoint;
        TokenPoint memory newPoint;
        LockedBalance memory _newLocked = LockedBalance(_oldLocked.amount, _oldLocked.start);

        // Case 1: new point same
        (oldPoint, newPoint) = curve.tokenCheckpoint(_tokenId, _oldLocked, _newLocked);

        // expect the point is overwritten but nothing actually changes
        assertEq(curve.tokenPointIntervals(_tokenId), 1, "C1: token interval incorrect");
        assertEq(newPoint.bias, _oldLocked.amount, "C1: bias incorrect");
        assertEq(newPoint.checkpointTs, _oldLocked.start, "C1: checkpointTs incorrect");
        assertEq(newPoint.writtenTs, _warp, "C1: writtenTs incorrect");
        assertEq(newPoint.coefficients[0], oldPoint.coefficients[0], "C1: constant incorrect");
        assertEq(newPoint.coefficients[1], oldPoint.coefficients[1], "C1: linear incorrect");
    }

    function testFuzz_case2_AmountGreaterSameStart(
        uint256 _tokenId,
        LockedBalance memory _oldLocked,
        uint32 _warp
    ) public {
        // Initialize state
        _setValidateState(_tokenId, _oldLocked, _warp);

        // Variables
        TokenPoint memory oldPoint;
        TokenPoint memory newPoint;
        LockedBalance memory _newLocked = LockedBalance(_oldLocked.amount + 1, _oldLocked.start);

        // Case 2: amount > old point, start same
        (oldPoint, newPoint) = curve.tokenCheckpoint(_tokenId, _oldLocked, _newLocked);

        // expectation: point overwritten but new curve
        assertEq(curve.tokenPointIntervals(_tokenId), 1, "C2: token interval incorrect");
        assertEq(newPoint.bias, _newLocked.amount, "C2: bias incorrect");
        assertEq(newPoint.checkpointTs, _oldLocked.start, "C2: checkpointTs incorrect");
        assertEq(newPoint.writtenTs, _warp, "C2: writtenTs incorrect");
        assertEq(
            newPoint.coefficients[0] / 1e18,
            curve.getCoefficients(_newLocked.amount)[0],
            "C2: constant incorrect"
        );
        assertEq(
            newPoint.coefficients[1] / 1e18,
            curve.getCoefficients(_newLocked.amount)[1],
            "C2: linear incorrect"
        );
    }

    function testFuzz_case3_AmountGreaterStartBefore(
        uint256 _tokenId,
        LockedBalance memory _oldLocked,
        uint32 _warp
    ) public {
        // Adjust assumptions for this case
        vm.assume(_oldLocked.start > 1); // start > 1 to avoid underflow
        _setValidateState(_tokenId, _oldLocked, _warp);

        // Variables
        TokenPoint memory oldPoint;
        TokenPoint memory newPoint;
        LockedBalance memory _newLocked = LockedBalance(
            _oldLocked.amount + 1,
            _oldLocked.start - 1
        );

        // expectation - can't do it
        vm.expectRevert(InvalidCheckpoint.selector);
        (oldPoint, newPoint) = curve.tokenCheckpoint(_tokenId, _oldLocked, _newLocked);
    }

    function testFuzz_case4_AmountGreaterStartAfter(
        uint256 _tokenId,
        LockedBalance memory _oldLocked,
        uint32 _warp
    ) public {
        // Initialize state
        _setValidateState(_tokenId, _oldLocked, _warp);

        // Variables
        TokenPoint memory oldPoint;
        TokenPoint memory newPoint;
        LockedBalance memory _newLocked = LockedBalance(
            _oldLocked.amount + 1,
            _oldLocked.start + 1
        );

        // Case 4: amount > old point, start after
        (oldPoint, newPoint) = curve.tokenCheckpoint(_tokenId, _oldLocked, _newLocked);

        // expectation: new point written
        assertEq(curve.tokenPointIntervals(_tokenId), 2, "C4: token interval incorrect");
        assertEq(newPoint.bias, _newLocked.amount, "C4: bias incorrect");
        assertEq(newPoint.checkpointTs, _newLocked.start, "C4: checkpointTs incorrect");
        assertEq(newPoint.writtenTs, _warp, "C4: writtenTs incorrect");
        assertEq(
            newPoint.coefficients[0] / 1e18,
            curve.getCoefficients(_newLocked.amount)[0],
            "C4: constant incorrect"
        );
        assertEq(
            newPoint.coefficients[1] / 1e18,
            curve.getCoefficients(_newLocked.amount)[1],
            "C4: linear incorrect"
        );
    }

    function testFuzz_case5_AmountLessSameStart(
        uint256 _tokenId,
        LockedBalance memory _oldLocked,
        uint32 _warp
    ) public {
        // Initialize state
        _setValidateState(_tokenId, _oldLocked, _warp);

        vm.assume(_oldLocked.amount > 0);

        // Variables
        TokenPoint memory oldPoint;
        TokenPoint memory newPoint;
        LockedBalance memory _newLocked = LockedBalance(_oldLocked.amount - 1, _oldLocked.start);

        // Case 5: amount < old point, start same
        console.log("oldLocked", _oldLocked.start, _oldLocked.amount);
        console.log("newLocked", _newLocked.start, _newLocked.amount);

        // expectation: overwrite with a smaller value
        (oldPoint, newPoint) = curve.tokenCheckpoint(_tokenId, _oldLocked, _newLocked);
    }

    function testFuzz_case6_AmountLessStartBefore(
        uint256 _tokenId,
        LockedBalance memory _oldLocked,
        uint32 _warp
    ) public {
        // Initialize state
        _setValidateState(_tokenId, _oldLocked, _warp);

        vm.assume(_oldLocked.start > 0); // start > 0 to avoid underflow
        vm.assume(_oldLocked.amount > 0);

        // Variables
        TokenPoint memory oldPoint;
        TokenPoint memory newPoint;
        LockedBalance memory _newLocked = LockedBalance(
            _oldLocked.amount - 1,
            _oldLocked.start - 1
        );

        // Case 6: amount less, start less
        // expect can't do
        vm.expectRevert(InvalidCheckpoint.selector);
        (oldPoint, newPoint) = curve.tokenCheckpoint(_tokenId, _oldLocked, _newLocked);
    }

    // Boilerplate for case 7: amount < old point, start after
    function testFuzz_case7_AmountLessStartAfter(
        uint256 _tokenId,
        LockedBalance memory _oldLocked,
        uint32 _warp
    ) public {
        // Initialize state
        _setValidateState(_tokenId, _oldLocked, _warp);

        vm.assume(_oldLocked.amount > 0);

        // Variables
        TokenPoint memory oldPoint;
        TokenPoint memory newPoint;
        LockedBalance memory _newLocked = LockedBalance(
            _oldLocked.amount - 1,
            _oldLocked.start + 1
        );

        // Case 7: amount less, start greater
        // expect new point written and lower
        (oldPoint, newPoint) = curve.tokenCheckpoint(_tokenId, _oldLocked, _newLocked);

        assertEq(curve.tokenPointIntervals(_tokenId), 2, "C7: token interval incorrect");
        assertEq(newPoint.bias, _newLocked.amount, "C7: bias incorrect");
        assertEq(newPoint.checkpointTs, _newLocked.start, "C7: checkpointTs incorrect");
        assertEq(newPoint.writtenTs, _warp, "C7: writtenTs incorrect");
        assertEq(
            newPoint.coefficients[0] / 1e18,
            curve.getCoefficients(_newLocked.amount)[0],
            "C7: constant incorrect"
        );
        assertEq(
            newPoint.coefficients[1] / 1e18,
            curve.getCoefficients(_newLocked.amount)[1],
            "C7: linear incorrect"
        );
    }

    // Boilerplate for case 8: amount = old point, start before
    function testFuzz_case8_AmountEqualStartBefore(
        uint256 _tokenId,
        LockedBalance memory _oldLocked,
        uint32 _warp
    ) public {
        // Initialize state
        _setValidateState(_tokenId, _oldLocked, _warp);

        vm.assume(_oldLocked.start > 0); // start > 0 to avoid underflow

        // Variables
        TokenPoint memory oldPoint;
        TokenPoint memory newPoint;
        LockedBalance memory _newLocked = LockedBalance(_oldLocked.amount, _oldLocked.start - 1);

        // start before so expect revert
        vm.expectRevert(InvalidCheckpoint.selector);
        (oldPoint, newPoint) = curve.tokenCheckpoint(_tokenId, _oldLocked, _newLocked);
    }

    // Boilerplate for case 9: amount = old point, start after
    function testFuzz_case9_AmountEqualStartAfter(
        uint256 _tokenId,
        LockedBalance memory _oldLocked,
        uint32 _warp
    ) public {
        // Initialize state
        _setValidateState(_tokenId, _oldLocked, _warp);

        // Variables
        TokenPoint memory oldPoint;
        TokenPoint memory newPoint;
        LockedBalance memory _newLocked = LockedBalance(_oldLocked.amount, _oldLocked.start + 1);

        // Case 9: amount = old point, start after
        // expect new point written
        (oldPoint, newPoint) = curve.tokenCheckpoint(_tokenId, _oldLocked, _newLocked);

        assertEq(curve.tokenPointIntervals(_tokenId), 2, "C9: token interval incorrect");
        assertEq(newPoint.bias, _newLocked.amount, "C9: bias incorrect");
        assertEq(newPoint.checkpointTs, _newLocked.start, "C9: checkpointTs incorrect");
        assertEq(newPoint.writtenTs, _warp, "C9: writtenTs incorrect");
        assertEq(
            newPoint.coefficients[0] / 1e18,
            curve.getCoefficients(_newLocked.amount)[0],
            "C9: constant incorrect"
        );
        assertEq(
            newPoint.coefficients[1] / 1e18,
            curve.getCoefficients(_newLocked.amount)[1],
            "C9: linear incorrect"
        );
    }

    function testFuzz_newAmountAtDifferentBlockTimestamp(
        uint256 _tokenId,
        LockedBalance memory _oldLocked,
        uint32 _warp,
        uint32 _change,
        uint128 _newAmount
    ) public {
        _setValidateState(_tokenId, _oldLocked, _warp);
        vm.assume(_oldLocked.start < type(uint32).max);

        TokenPoint memory oldPoint;
        TokenPoint memory newPoint;

        uint48 warpTime = uint48(_warp) + uint48(_change);

        vm.warp(warpTime);

        LockedBalance memory _newLocked = LockedBalance(_newAmount, _oldLocked.start);
        (oldPoint, newPoint) = curve.tokenCheckpoint(_tokenId, _oldLocked, _newLocked);

        // expectation: new point written with new bias
        assertEq(curve.tokenPointIntervals(_tokenId), 1, "C10: token interval incorrect");

        uint elapsed = (_oldLocked.start > block.timestamp)
            ? 0
            : block.timestamp - _oldLocked.start;

        uint newBias = curve.getBias(elapsed, _newAmount);
        uint oldBias = curve.getBias(elapsed, _oldLocked.amount);

        assertEq(newPoint.bias, newBias, "C10: new bias incorrect");

        // if the new amount is the same, should be equivalent to the old lock
        if (_newAmount == _oldLocked.amount) {
            assertEq(newBias, oldBias, "C10: old and new bias should be the same");
        }
        // if the new amount is less then the bias should be less than the equivalent
        else if (_newAmount < _oldLocked.amount) {
            assertLt(newBias, oldBias, "C10: new bias should be less than old bias");
        }
        // if the new amount is greater then the bias should be greater than the equivalent
        else {
            assertGt(newBias, oldBias, "C10: new bias should be greater than old bias");
        }

        assertEq(newPoint.checkpointTs, _oldLocked.start, "C10: checkpointTs incorrect");
        assertEq(newPoint.writtenTs, warpTime, "C10: writtenTs incorrect");
        assertEq(
            newPoint.coefficients[0] / 1e18,
            curve.getCoefficients(_newLocked.amount)[0],
            "C10: constant incorrect"
        );
        assertEq(
            newPoint.coefficients[1] / 1e18,
            curve.getCoefficients(_newLocked.amount)[1],
            "C10: linear incorrect"
        );
    }

    function testFuzz_exit(
        uint256 _tokenId,
        LockedBalance memory _oldLocked,
        uint32 _warp,
        uint32 _exit
    ) public {
        // Initialize state
        _setValidateState(_tokenId, _oldLocked, _warp);

        vm.assume(_oldLocked.start < type(uint32).max);

        // Variables
        TokenPoint memory oldPoint;
        TokenPoint memory newPoint;

        uint48 warpTime = uint48(_warp) + uint48(_exit);

        vm.warp(warpTime);

        LockedBalance memory _newLocked = LockedBalance(0, _oldLocked.start + _exit);
        (oldPoint, newPoint) = curve.tokenCheckpoint(_tokenId, _oldLocked, _newLocked);

        // expectation: new point written and everything cleared out
        assertEq(
            curve.tokenPointIntervals(_tokenId),
            _exit == 0 ? 1 : 2,
            "exit: token interval incorrect"
        );
        assertEq(newPoint.bias, 0, "exit: bias incorrect");
        assertEq(newPoint.checkpointTs, _oldLocked.start + _exit, "exit: checkpointTs incorrect");
        assertEq(newPoint.writtenTs, warpTime, "exit: writtenTs incorrect");
        assertEq(newPoint.coefficients[0], 0, "exit: constant incorrect");
        assertEq(newPoint.coefficients[1], 0, "exit: linear incorrect");
    }

    // think deeply about different TIMES of writing, not just checkpoints
}
