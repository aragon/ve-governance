// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/*///////////////////////////////////////////////////////////////
                        METADATA
//////////////////////////////////////////////////////////////*/

interface IMetadataEvents {
    /// @notice Event emmited when the base metadata URI is updated
    /// @param uri New base URI
    event BaseURISet(string uri);
}

/*///////////////////////////////////////////////////////////////
                        WHITELIST
//////////////////////////////////////////////////////////////*/
interface IWhitelistEvents {
    event WhitelistSet(address indexed account, bool status);
}

interface IWhitelistErrors {
    error NotWhitelisted();
    error ForbiddenWhitelistAddress();
}

interface IWhitelist is IWhitelistEvents, IWhitelistErrors {
    /// @notice Set whitelist status for an address
    function setWhitelisted(address addr, bool isWhitelisted) external;

    /// @notice Check if an address is whitelisted
    function whitelisted(address addr) external view returns (bool);
}

interface IMetadata is IMetadataEvents {}

interface ILock is IWhitelist, IMetadata {
    error OnlyEscrow();

    /// @notice Address of the escrow contract that holds underyling assets
    function escrow() external view returns (address);
}
