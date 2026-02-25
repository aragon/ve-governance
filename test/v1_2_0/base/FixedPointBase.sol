// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

// TODO: come up with better name..
contract FixedPointBase {
    using SafeCast for int256;
    using SafeCast for uint256;

    uint256 maxTime;
    uint256 checkpointInterval;
    int256 linearCoefficient;

    function setMultiplier(int256 _linearCoefficient) public {
        linearCoefficient = _linearCoefficient;
    }

    function initialize(uint256 _maxTime, uint256 _checkpointInterval) public {
        maxTime = _maxTime;
        checkpointInterval = _checkpointInterval;
    }

    function initialize(uint256 _maxTime, uint256 _checkpointInterval, int256 _linearCoefficient) public {
        maxTime = _maxTime;
        checkpointInterval = _checkpointInterval;
        setMultiplier(_linearCoefficient);
    }

    function slopeFP(uint256 _amount) internal view returns (int256) {
        if (maxTime == 0) return 0;

        return _amount.toInt256() * linearCoefficient;
    }

    function biasFP(uint256 _amount, uint256 _duration) internal view returns (int256) {
        int256 slope = maxTime == 0 ? int256(0) : _amount.toInt256() * linearCoefficient;
        return _amount.toInt256() * int256(1e18) + slope * _duration.toInt256();
    }

    function bias(uint256 _amount, uint256 _duration) internal view returns (uint256 bias_) {
        return (biasFP(_amount, _duration) / 1e18).toUint256();
    }

    function weekStartTs(uint256 _time) internal view returns (uint256) {
        return (_time / checkpointInterval) * checkpointInterval;
    }

    // bias's increase stops after `_startTime + maxTime`. In case `maxTime` is small
    // such that `_startTime + maxTime` ends up being less than `writtenTs`. That means that
    // it has already stopped at the time of writing a new point. In such case, we return
    // bigger or equal value of `_writtenTs`. Otherwise, if we always warp to
    // `_startTime + maxTime`, this can cause underflow/overflow in the `curve`'s checkpoint function.
    function getEndTimestamp(
        uint256 _startTimeTs,
        uint256 _writtenTs,
        uint256 _extra
    ) internal view returns (uint256) {
        if (_startTimeTs + maxTime >= _writtenTs) {
            return _startTimeTs + maxTime + _extra;
        }

        return _writtenTs + _extra;
    }

    function getEndTimestamp(
        uint256 _startTimeTs,
        uint256 _writtenTs
    ) internal view returns (uint256) {
        return getEndTimestamp(_startTimeTs, _writtenTs, 0);
    }
}
