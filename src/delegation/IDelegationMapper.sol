/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IDelegationMapper {
    function delegate(uint256 _tokenId, address _delegate) external;

    function pull(uint256 _tokenId) external;

    function moveDelegateVotes(address _from, address _to, uint256 _tokenId) external;

    error OnlyEscrow();
}

interface IVotes {
    function getVotes(address account) external view returns (uint256);

    function getPastVotes(address account, uint256 timepoint) external view returns (uint256);

    function getPastTotalSupply(uint256 timepoint) external view returns (uint256);
}
