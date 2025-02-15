/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// interfaces
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IClock, IClockSeason} from "./IClock.sol";

// contracts
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {DaoAuthorizableUpgradeable as DaoAuthorizable} from "@aragon/osx/core/plugin/dao-authorizable/DaoAuthorizableUpgradeable.sol";

/// @title Clock
contract Clock is IClock, DaoAuthorizable, UUPSUpgradeable, IClockSeason {
    bytes32 public constant CLOCK_ADMIN_ROLE = keccak256("CLOCK_ADMIN_ROLE");

    /// @dev Epoch encompasses a voting and non-voting period
    uint256 internal constant EPOCH_DURATION = 2 weeks;

    /// @dev Checkpoint interval is the time between each voting checkpoint
    uint256 internal constant CHECKPOINT_INTERVAL = 1 weeks;

    /// @dev Voting duration is the time during which votes can be cast
    uint256 internal constant VOTE_DURATION = 1 weeks;

    /// @dev Opens and closes the voting window slightly early to avoid timing attacks
    uint256 internal constant VOTE_WINDOW_BUFFER = 1 hours;

    /// @dev Seasons array
    uint48[] private seasons;

    /*///////////////////////////////////////////////////////////////
                            Initialization
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _dao) external initializer {
        __DaoAuthorizableUpgradeable_init(IDAO(_dao));
        // uups not needed
    }

    /*///////////////////////////////////////////////////////////////
                            Getters
    //////////////////////////////////////////////////////////////*/

    function epochDuration() external pure returns (uint256) {
        return EPOCH_DURATION;
    }

    function checkpointInterval() external pure returns (uint256) {
        return CHECKPOINT_INTERVAL;
    }

    function voteDuration() external pure returns (uint256) {
        return VOTE_DURATION;
    }

    function voteWindowBuffer() external pure returns (uint256) {
        return VOTE_WINDOW_BUFFER;
    }

    /*///////////////////////////////////////////////////////////////
                            Epochs
    //////////////////////////////////////////////////////////////*/

    function currentEpoch() external view returns (uint256) {
        return resolveEpoch(block.timestamp);
    }

    function resolveEpoch(uint256 timestamp) public pure returns (uint256) {
        unchecked {
            return timestamp / EPOCH_DURATION;
        }
    }

    function elapsedInEpoch() external view returns (uint256) {
        return resolveElapsedInEpoch(block.timestamp);
    }

    function resolveElapsedInEpoch(uint256 timestamp) public pure returns (uint256) {
        unchecked {
            return timestamp % EPOCH_DURATION;
        }
    }

    function epochStartsIn() external view returns (uint256) {
        return resolveEpochStartsIn(block.timestamp);
    }

    /// @notice Number of seconds until the start of the next epoch (relative)
    /// @dev If exactly at the start of the epoch, returns 0
    function resolveEpochStartsIn(uint256 timestamp) public pure returns (uint256) {
        unchecked {
            uint256 elapsed = resolveElapsedInEpoch(timestamp);
            return (elapsed == 0) ? 0 : EPOCH_DURATION - elapsed;
        }
    }

    function epochStartTs() external view returns (uint256) {
        return resolveEpochStartTs(block.timestamp);
    }

    /// @notice Timestamp of the start of the next epoch (absolute)
    function resolveEpochStartTs(uint256 timestamp) public pure returns (uint256) {
        unchecked {
            return timestamp + resolveEpochStartsIn(timestamp);
        }
    }

    /*///////////////////////////////////////////////////////////////
                              Voting
    //////////////////////////////////////////////////////////////*/

    function votingActive() external view returns (bool) {
        return resolveVotingActive(block.timestamp);
    }

    function resolveVotingActive(uint256 timestamp) public pure returns (bool) {
        bool afterVoteStart = timestamp >= resolveEpochVoteStartTs(timestamp);
        bool beforeVoteEnd = timestamp < resolveEpochVoteEndTs(timestamp);
        return afterVoteStart && beforeVoteEnd;
    }

    function epochVoteStartsIn() external view returns (uint256) {
        return resolveEpochVoteStartsIn(block.timestamp);
    }

    /// @notice Number of seconds until voting starts.
    /// @dev If voting is active, returns 0.
    function resolveEpochVoteStartsIn(uint256 timestamp) public pure returns (uint256) {
        unchecked {
            uint256 elapsed = resolveElapsedInEpoch(timestamp);

            // if less than the offset has past, return the time until the offset
            if (elapsed < VOTE_WINDOW_BUFFER) {
                return VOTE_WINDOW_BUFFER - elapsed;
            }
            // if voting is active (we are in the voting period) return 0
            else if (elapsed < VOTE_DURATION - VOTE_WINDOW_BUFFER) {
                return 0;
            }
            // else return the time until the next epoch + the offset
            else return resolveEpochStartsIn(timestamp) + VOTE_WINDOW_BUFFER;
        }
    }

    function epochVoteStartTs() external view returns (uint256) {
        return resolveEpochVoteStartTs(block.timestamp);
    }

    /// @notice Timestamp of the start of the next voting period (absolute)
    function resolveEpochVoteStartTs(uint256 timestamp) public pure returns (uint256) {
        unchecked {
            return timestamp + resolveEpochVoteStartsIn(timestamp);
        }
    }

    function epochVoteEndsIn() external view returns (uint256) {
        return resolveEpochVoteEndsIn(block.timestamp);
    }

    /// @notice Number of seconds until the end of the current voting period (relative)
    /// @dev If we are outside the voting period, returns 0
    function resolveEpochVoteEndsIn(uint256 timestamp) public pure returns (uint256) {
        unchecked {
            uint256 elapsed = resolveElapsedInEpoch(timestamp);
            uint VOTING_WINDOW = VOTE_DURATION - VOTE_WINDOW_BUFFER;
            // if we are outside the voting period, return 0
            if (elapsed >= VOTING_WINDOW) return 0;
            // if we are in the voting period, return the remaining time
            else return VOTING_WINDOW - elapsed;
        }
    }

    function epochVoteEndTs() external view returns (uint256) {
        return resolveEpochVoteEndTs(block.timestamp);
    }

    /// @notice Timestamp of the end of the current voting period (absolute)
    function resolveEpochVoteEndTs(uint256 timestamp) public pure returns (uint256) {
        unchecked {
            return timestamp + resolveEpochVoteEndsIn(timestamp);
        }
    }

    /*///////////////////////////////////////////////////////////////
                            Checkpointing
    //////////////////////////////////////////////////////////////*/

    function epochNextCheckpointIn() external view returns (uint256) {
        return resolveEpochNextCheckpointIn(block.timestamp);
    }

    /// @notice Number of seconds until the next checkpoint interval (relative)
    /// @dev If exactly at the start of the checkpoint interval, returns 0
    function resolveEpochNextCheckpointIn(uint256 timestamp) public pure returns (uint256) {
        unchecked {
            uint256 elapsed = resolveElapsedInEpoch(timestamp);
            // elapsed > deposit interval, then subtract the interval
            if (elapsed >= CHECKPOINT_INTERVAL) elapsed -= CHECKPOINT_INTERVAL;
            return CHECKPOINT_INTERVAL - elapsed;
        }
    }

    function epochNextCheckpointTs() external view returns (uint256) {
        return resolveEpochNextCheckpointTs(block.timestamp);
    }

    /// @notice Timestamp of the next deposit interval (absolute)
    function resolveEpochNextCheckpointTs(uint256 timestamp) public pure returns (uint256) {
        unchecked {
            return timestamp + resolveEpochNextCheckpointIn(timestamp);
        }
    }

    /*///////////////////////////////////////////////////////////////
                            Seasons
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the current season index
    /// @dev The season index starts at 0
    function currentSeason() external view returns (uint16) {
        return IClockSeason(this).seasonAt(uint48(block.timestamp));
    }

    /// @notice Returns a season's start and end timestamps by index
    /// @dev The startTimestamp of the first season is always 0
    /// @dev The endTimestamp of the current season is always 0
    function season(uint16 seasonIndex) external view returns (uint48 startTimestamp, uint48 endTimestamp) {
        if (seasonIndex > seasons.length) {
            revert SeasonNotFound();
        }
        startTimestamp = seasonIndex == 0 ? 0 : seasons[seasonIndex - 1];
        endTimestamp = seasonIndex < seasons.length ? seasons[seasonIndex] : 0;
    }

    /// @notice Returns the season index at a given timestamp
    /// @dev The season index starts at 0 but the season index as 1 is indexed as 0 in the array
    /// @dev If the timestamp is after the last season, returns the length of the seasons array
    function seasonAt(uint48 _timestamp) external view returns (uint16) {
        for (uint16 i = 0; i < seasons.length; i++) {
            if (_timestamp < seasons[i]) {
                return i;
            }
        }
        return uint16(seasons.length);
    }

    /// @notice Creates a new season
    /// @dev The season duration must be greater than EPOCH_DURATION
    function newSeason() external auth(CLOCK_ADMIN_ROLE) {
        uint256 startTime = IClock(this).epochNextCheckpointTs();

        if (seasons.length > 0) {
            uint48 lastSeason = seasons[seasons.length - 1];
            if (startTime < lastSeason + EPOCH_DURATION) {
                revert SeasonTooShort();
            }
        }
        seasons.push(uint48(startTime));

        emit SeasonStarted(uint16(seasons.length), uint48(startTime));
    }

    /*///////////////////////////////////////////////////////////////
                            UUPS Getters
    //////////////////////////////////////////////////////////////*/

    function _authorizeUpgrade(address) internal override auth(CLOCK_ADMIN_ROLE) {}

    function implementation() external view returns (address) {
        return _getImplementation();
    }

    uint256[50] private __gap;
}
