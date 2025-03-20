// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

// TODO: GIORGI come up with better name..
contract FixedPointBase  {
    
    uint256 maxTime;
    uint256 checkpointInterval;

    function initialize(uint256 _maxTime, uint256 _checkpointInterval) public {
        maxTime = _maxTime;
        checkpointInterval = _checkpointInterval;
    }
    
    function slopeFP(uint256 _amount) internal view returns (int256) {
        return int256(_amount * (1e18 / maxTime));
    }

    function biasFP(uint256 _amount, uint256 _duration) internal view returns (int256) {
        return int256(_amount * 1e18 + ((_amount * (1e18 / maxTime)) * _duration));
    }

    function bias(uint256 _amount, uint256 _duration) internal view returns (uint256 bias_) {
        return uint256(biasFP(_amount, _duration) / 1e18);
    }

    function weekStartTs(uint256 _time) internal view returns (uint256) {
        return (_time / checkpointInterval) * checkpointInterval;
    }

    // function assertTotalSupply(uint256 _t, int256 _amountFP) internal view {
    //     assertEq(curve.supplyAt(_t), uint256(_amountFP / 1e18));
    // }

    // function assertVotingPower(uint256 _tokenId, uint256 _t, int256 _amountFP) internal view {
    //     assertEq(curve.votingPowerAt(_tokenId, _t), uint256(_amountFP / 1e18));
    // }
}
