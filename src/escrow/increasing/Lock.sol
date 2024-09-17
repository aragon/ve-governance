/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ERC721EnumerableUpgradeable as ERC721Enumerable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract Lock is ERC721Enumerable, UUPSUpgradeable {
    /// @dev enables transfers without whitelisting
    address public constant WHITELIST_ANY_ADDRESS =
        address(uint160(uint256(keccak256("WHITELIST_ANY_ADDRESS"))));

    /// @notice Decimals of the voting power
    // uint8 public constant decimals = 18;

    address public escrow;
    mapping(address => bool) public whitelisted;

    modifier auth() {
        require(msg.sender == escrow, "Lock: not authorized");
        _;
    }

    /// @notice Whitelisted contracts that are allowed to transfer

    function supportsInterface(
        bytes4 _interfaceId
    ) public view override(ERC721Enumerable) returns (bool) {
        return super.supportsInterface(_interfaceId);
    }

    // constructor() {
    //     _disableInitializers();
    // }

    function initialize(
        address _escrow,
        string memory _name,
        string memory _symbol
    ) external initializer {
        __ERC721_init(_name, _symbol);
        escrow = _escrow;

        // allow sending nfts to the escrow
        whitelisted[escrow] = true;
        emit WhitelistSet(address(this), true);
    }

    /// @notice Transfers disabled by default, only whitelisted addresses can receive transfers
    function setWhitelisted(address _account, bool _isWhitelisted) external auth {
        whitelisted[_account] = _isWhitelisted;
        emit WhitelistSet(_account, _isWhitelisted);
    }

    // function enableTransfers() external auth {
    //     whitelisted[WHITELIST_ANY_ADDRESS] = true;
    //     emit WhitelistSet(WHITELIST_ANY_ADDRESS, true);
    // }

    // function isApprovedOrOwner(address _spender, uint256 _tokenId) external view returns (bool) {
    //     return _isApprovedOrOwner(_spender, _tokenId);
    // }

    /// @dev Override the transfer to check if the recipient is whitelisted
    /// This avoids needing to check for mint/burn but is less idomatic than beforeTokenTransfer
    function _transfer(address _from, address _to, uint256 _tokenId) internal override {
        if (whitelisted[WHITELIST_ANY_ADDRESS] || whitelisted[_to]) {
            super._transfer(_from, _to, _tokenId);
        } else revert NotWhitelisted();
    }

    function mint(address _to, uint256 _tokenId) external auth {
        _mint(_to, _tokenId);
    }

    function burn(uint256 _tokenId) external auth {
        _burn(_tokenId);
    }

    event WhitelistSet(address indexed account, bool status);
    error NotWhitelisted();

    /// @notice Returns the address of the implementation contract in the [proxy storage slot](https://eips.ethereum.org/EIPS/eip-1967) slot the [UUPS proxy](https://eips.ethereum.org/EIPS/eip-1822) is pointing to.
    /// @return The address of the implementation contract.
    function implementation() public view returns (address) {
        return _getImplementation();
    }

    /// @notice Internal method authorizing the upgrade of the contract via the [upgradeability mechanism for UUPS proxies](https://docs.openzeppelin.com/contracts/4.x/api/proxy#UUPSUpgradeable) (see [ERC-1822](https://eips.ethereum.org/EIPS/eip-1822)).
    function _authorizeUpgrade(address) internal virtual override auth {}
}
