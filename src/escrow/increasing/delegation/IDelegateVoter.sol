// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.0;

import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";
import {IERC4906} from "@openzeppelin/contracts/interfaces/IERC4906.sol";
import {IVotes} from "../interfaces/IVotes.sol";

interface IDelegateVoterErrors {
    error SignatureExpired();
    error InvalidNonce();
    error InvalidSignature();
    error InvalidSignatureS();
}

interface ICheckpoint {
    /// @notice A checkpoint for recorded delegated voting weights at a certain timestamp
    struct Checkpoint {
        uint256 fromTimestamp;
        address owner;
        uint256 delegatedBalance;
        uint256 delegatee;
    }
}

interface IDelegateVoter is ICheckpoint, IERC6372, IVotes, IDelegateVoterErrors {
    /// @notice The number of checkpoints for each tokenId
    function numCheckpoints(uint256 tokenId) external view returns (uint48);

    /// @notice A record of states for signing / validating signatures
    function nonces(address account) external view returns (uint256);

    function delegates(uint256 delegator) external view returns (uint256);

    function checkpoints(uint256 tokenId, uint48 index) external view returns (Checkpoint memory);

    function getPastVotes(address account, uint256 tokenId, uint256 timestamp) external view returns (uint256);

    function getPastTotalSupply(uint256 timestamp) external view returns (uint256);

    function delegate(uint256 delegator, uint256 delegatee) external;

    function delegateBySig(
        uint256 delegator,
        uint256 delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /// @inheritdoc IERC6372
    function clock() external view returns (uint48);

    /// @inheritdoc IERC6372
    function CLOCK_MODE() external view returns (string memory);
}
