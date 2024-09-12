/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IClockUser {
    function clock() external view returns (address);
}

interface IClock {
    function currentEpoch() external view returns (uint256);

    function elapsedInEpoch() external view returns (uint256);

    function epochStartsIn() external view returns (uint256);

    function epochStartTs() external view returns (uint256);

    function votingActive() external view returns (bool);

    function epochVoteStartsIn() external view returns (uint256);

    function epochVoteStartTs() external view returns (uint256);

    function epochVoteEndsIn() external view returns (uint256);

    function epochVoteEndTs() external view returns (uint256);

    function epochNextCheckpointIn() external view returns (uint256);

    function epochNextCheckpointTs() external view returns (uint256);

    function epochDuration() external pure returns (uint256);

    function checkpointInterval() external pure returns (uint256);

    function voteDuration() external pure returns (uint256);

    function voteWindowOffset() external pure returns (uint256);
}
