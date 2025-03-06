pragma solidity ^0.8.0;

/*///////////////////////////////////////////////////////////////
                        METADATA
//////////////////////////////////////////////////////////////*/

interface IMetadataEvents {
    /// @notice Event emmited when the base metadata URI is updated
    /// @param uri New base URI
    event BaseURISet(string uri);
}
