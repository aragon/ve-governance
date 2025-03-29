/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IDelegationMapperErrorsAndEvents {
    event AutoDelegationSet(address indexed delegate, bool enabled);
    error OnlyEscrow();

    error DelegateBySigNotSupported();
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
