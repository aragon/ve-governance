/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IVotingEscrowIncreasing.sol";

interface IVotingEscrowExiting {
    /// @notice How much amount has been exiting.
    /// @return total The total amount for which beginWithdrawal has been called
    ///         but withdraw has not yet been executed.
    function currentExitingAmount() external view returns (uint256);
}

interface IDelegationMapper {
    /// @notice Called upon the transfer to update delegation checkpoints.
    /// TODO: GIORGI add natspec for params.
    function moveDelegateVotes(address _from, address _to, uint256 _tokenId) external;
}

interface IMergeEventsAndErrors {
    event Merged(
        address indexed _sender,
        uint256 indexed _from,
        uint256 indexed _to,
        uint208 _amountFrom,
        uint208 _amountTo,
        uint208 _amountFinal
    );

    error CannotMerge(uint256 _from, uint256 _to);
    error SameNFT();
}

interface IMerge is ILockedBalanceIncreasing, IMergeEventsAndErrors {
    /// @notice Merge two tokens - i.e  `from` into `_to`.
    /// @param _from The token id from which merge is occuring
    /// @param _to The token id to which `_from` is merging
    function merge(uint256 _from, uint256 _to) external;

    /// @notice Whether 2 tokens can be merged.
    /// @param _from The token id from which merge should occur.
    /// @param _to The token id to which `_from` should merge.
    function canMerge(
        LockedBalance memory _from,
        LockedBalance memory _to
    ) external view returns (bool);
}

interface ISplitEventsAndErrors {
    event Split(
        uint256 indexed _from,
        uint256 indexed _tokenId1,
        uint256 indexed _tokenId2,
        address _sender,
        uint208 _splitAmount1,
        uint208 _splitAmount2
    );

    event SplitWhitelistSet(address indexed account, bool status);

    error SplitNotWhitelisted();
    error SplitAmountTooBig();
}

interface ISplit is ISplitEventsAndErrors {
    /// @notice Split token into two new, separate tokens.
    /// @param _from The token id that should be split
    /// @param _value The amount that determines how token is split
    /// @return _tokenId1 The token id of first token after splitting
    /// @return _tokenId2 The token id of second token after splitting
    function split(
        uint256 _from,
        uint256 _value
    ) external returns (uint256 _tokenId1, uint256 _tokenId2);
}

interface IVotingEscrowIncreasingV1_4_0 is
    IVotingEscrowIncreasing,
    IVotingEscrowExiting,
    IMerge,
    ISplit,
    IDelegationMapper
{}
