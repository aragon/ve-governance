/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IClock.sol";

interface IClockV1_2_0 is IClock {
    function epochPrevCheckpointTs() external view returns (uint256);

    function resolveEpochPrevCheckpointTs(uint256 timestamp) external pure returns (uint256);
}
