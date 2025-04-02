/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IDelegationMapperErrorsAndEvents {
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

interface IDelegationMapperStorage {
    struct GlobalPoint {
        int256 bias;
        int256 slope;
        uint48 writtenTs;
    }
}

interface IDelegationMapper is IDelegationMapperErrorsAndEvents, IDelegationMapperStorage {
    function delegate(uint256[] calldata _tokenIds) external;

    function moveDelegateVotes(address _from, address _to, uint256 _tokenId) external;
}
