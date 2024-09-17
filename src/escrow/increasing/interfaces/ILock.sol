// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/*///////////////////////////////////////////////////////////////
                        WHITELIST
//////////////////////////////////////////////////////////////*/
interface IWhitelistEvents {
    event WhitelistSet(address indexed account, bool status);
}

interface IWhitelistErrors {
    error NotWhitelisted();
}

interface IWhitelist is IWhitelistEvents, IWhitelistErrors {
    /// @notice Set whitelist status for an address
    function setWhitelisted(address addr, bool isWhitelisted) external;

    /// @notice Check if an address is whitelisted
    function whitelisted(address addr) external view returns (bool);
}

interface ILock is IWhitelist {
    error OnlyEscrow();

    /// @notice Address of the escrow contract that holds underyling assets
    function escrow() external view returns (address);
}
