/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IClockUser {
    function clock() external view returns (address);
}

interface IClock {
    function epochDuration() external pure returns (uint256);

    function checkpointInterval() external pure returns (uint256);

    function voteDuration() external pure returns (uint256);

    function voteWindowBuffer() external pure returns (uint256);

    function currentEpoch() external view returns (uint256);

    function resolveEpoch(uint256 timestamp) external pure returns (uint256);

    function elapsedInEpoch() external view returns (uint256);

    function resolveElapsedInEpoch(uint256 timestamp) external pure returns (uint256);

    function epochStartsIn() external view returns (uint256);

    function resolveEpochStartsIn(uint256 timestamp) external pure returns (uint256);

    function epochStartTs() external view returns (uint256);

    function resolveEpochStartTs(uint256 timestamp) external pure returns (uint256);

    function votingActive() external view returns (bool);

    function resolveVotingActive(uint256 timestamp) external pure returns (bool);

    function epochVoteStartsIn() external view returns (uint256);

    function resolveEpochVoteStartsIn(uint256 timestamp) external pure returns (uint256);

    function epochVoteStartTs() external view returns (uint256);

    function resolveEpochVoteStartTs(uint256 timestamp) external pure returns (uint256);

    function epochVoteEndsIn() external view returns (uint256);

    function resolveEpochVoteEndsIn(uint256 timestamp) external pure returns (uint256);

    function epochVoteEndTs() external view returns (uint256);

    function resolveEpochVoteEndTs(uint256 timestamp) external pure returns (uint256);

    function epochNextCheckpointIn() external view returns (uint256);

    function resolveEpochNextCheckpointIn(uint256 timestamp) external pure returns (uint256);

    function epochNextCheckpointTs() external view returns (uint256);

    function resolveEpochNextCheckpointTs(uint256 timestamp) external pure returns (uint256);
}

interface ISeasonEvents {
    event SeasonStarted(uint16 seasonIndex, uint48 startTimestamp);
    event SeasonDurationSet(uint48 duration);
}

interface IClockSeason is ISeasonEvents {
    function currentSeason() external view returns (uint16);

    // endTimestamp can be 0 if the season is still active
    function season(
        uint16 seasonIndex
    ) external view returns (uint48 startTimestamp, uint48 endTimestamp);

    // all seasons
    //function seasons() external view returns (uint48[] memory startTimestamps);

    function seasonAt(uint48 _timestamp) external view returns (uint16 season);

    // activates a new season
    function newSeason() external;

    //function minSeasonDuration() external view returns (uint48 minDuration);

    function setMinSeasonDuration(uint48 _newDuration) external;
}
