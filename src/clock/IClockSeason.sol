/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ISeasonEvents {
    event SeasonStarted(uint16 seasonIndex, uint48 startTimestamp);
    event SeasonDurationSet(uint48 duration);
}

interface ISeasonErrors {
    error SeasonTooShort();
    error SeasonNotFound();
}

interface IClockSeason is ISeasonEvents, ISeasonErrors {
    function currentSeasonTs() external view returns (uint48 startTimestamp, uint48 endTimestamp);

    function currentSeasonIndex() external view returns (uint16 seasonIndex);

    function seasonTs(
        uint16 seasonIndex
    ) external view returns (uint48 startTimestamp, uint48 endTimestamp);

    function seasonTsAt(
        uint48 _timestamp
    ) external view returns (uint48 startTimestamp, uint48 endTimestamp);

    function seasonIndexAt(uint48 _timestamp) external view returns (uint16 seasonIndex);

    function newSeason() external returns (uint48 startTimestamp, uint16 seasonIndex);
}
