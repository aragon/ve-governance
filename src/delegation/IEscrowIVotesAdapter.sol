/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

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
    function moveDelegateVotes(address _from, address _to, uint256 _tokenId) external;
}

interface IEscrowIVotesAdapterStorage {
    struct GlobalPoint {
        int256 bias;
        int256 slope;
        uint48 writtenTs;
    }
}

interface IEscrowIVotesAdapter is IEscrowIVotesAdapterErrorsAndEvents, IEscrowIVotesAdapterStorage, IDelegateMoveVote {
    function delegate(uint256[] calldata _tokenIds) external;

    function undelegate(uint256[] calldata _tokenIds) external;
}
