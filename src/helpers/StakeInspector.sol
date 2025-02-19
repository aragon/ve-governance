/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IVotingEscrowIncreasing} from "@escrow-interfaces/IVotingEscrowIncreasing.sol";

interface IVotingEscrowIncreasingExtended is IVotingEscrowIncreasing {
    function ownedTokens(address _account) external view returns (uint256[] memory tokenIds);
}

/// @notice Aggregate staked balances for an address given multiple veNFTs
contract StakeInspector {
    /// @notice The staking contract
    IVotingEscrowIncreasingExtended public escrow;

    constructor(address _escrow) {
        escrow = IVotingEscrowIncreasingExtended(_escrow);
    }

    /// @notice Fetch the total underlying tokens staked across all the veNFTs owned by an account
    function getTotalStaked(address _account) external view returns (uint256) {
        uint256 totalStaked = 0;

        uint256[] memory veNFTs = escrow.ownedTokens(_account);
        for (uint256 i = 0; i < veNFTs.length; i++) {
            totalStaked += escrow.locked(veNFTs[i]).amount;
        }
        return totalStaked;
    }
}
