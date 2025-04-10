/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    IVotesUpgradeable
} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

interface IEscrowIVotesAdapterErrorsAndEvents {
    event AutoDelegationSet(address indexed delegate, bool enabled);
    event TokensDelegated(address indexed sender, address indexed delegatee, uint256[] tokenIds);
    event TokensUndelegated(address indexed sender, address indexed delegatee, uint256[] tokenIds);

    error OnlyEscrow();

    error DelegateBySigNotSupported();

    error NotApprovedOrOwner();
    error InvalidTokenId();
    error DelegationNotAllowed();
    error DelegateeNotSet();

    error TokenAlreadyDelegated(uint256 tokenId);
    error TokenNotDelegated(uint256 tokenId);
}

interface IDelegateMoveVote {
    /// @notice After a token transfer, decreases `_from`'s voting power and increases `_to`'s voting power.
    /// @dev Called upon a token transfer.
    /// @param _from The current delegatee of `_tokenId`.
    /// @param _to The new delegatee of `_tokenId`
    /// @param _tokenId The token id that is being transferred.
    function moveDelegateVotes(address _from, address _to, uint256 _tokenId) external;
}

interface IDelegateUpdateVotingPower {
    /// @notice Updates current voting power of `_from` and `_to`.
    /// @dev Called upon a token transfer and delegate/undelegate.
    function updateVotingPower(address _from, address _to) external;
}

interface IEscrowIVotesAdapterStorage {
    struct GlobalPoint {
        int256 bias;
        int256 slope;
        uint48 writtenTs;
    }
}

interface IEscrowIVotesAdapter is IEscrowIVotesAdapterErrorsAndEvents, IEscrowIVotesAdapterStorage, IDelegateMoveVote, IVotesUpgradeable {
    /// @notice Allows to delegate `_tokenIds` to the current delegatee 
    ///         which is set by IVotes's `delegate` function.
    /// @param _tokenIds The list of token ids that are being delegated.
    function delegate(uint256[] calldata _tokenIds) external;

    /// @notice Allows to un-delegate `_tokenIds` from the current delegatee 
    ///         which was set by delegate.
    /// @param _tokenIds The list of token ids that are being un-delegated.
    function undelegate(uint256[] calldata _tokenIds) external;

    /// @notice Check if the token is currently delegated or not.
    function tokenIsDelegated(uint256 _tokenId) external view returns(bool);
}
