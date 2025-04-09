/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IClock.sol";
import {IClockSeason} from "./IClockSeason.sol";

interface IClockV1_2_0 is IClock, IClockSeason {
    function epochPrevCheckpointTs() external view returns (uint256);

    function resolveEpochPrevCheckpointTs(uint256 timestamp) external pure returns (uint256);
}
