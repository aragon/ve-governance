/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ILock} from "@escrow-interfaces/ILock.sol";
import {ERC721EnumerableUpgradeable as ERC721Enumerable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {DaoAuthorizableUpgradeable as DaoAuthorizable} from "@aragon/osx/core/plugin/dao-authorizable/DaoAuthorizableUpgradeable.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";

/// @title NFT representation of an escrow locking mechanism
contract Lock is ILock, ERC721Enumerable, UUPSUpgradeable, DaoAuthorizable {
    /// @dev enables transfers without whitelisting
    address public constant WHITELIST_ANY_ADDRESS =
        address(uint160(uint256(keccak256("WHITELIST_ANY_ADDRESS"))));

    /// @notice role to upgrade this contract
    bytes32 public constant LOCK_ADMIN_ROLE = keccak256("LOCK_ADMIN");

    /// @notice Address of the escrow contract that holds underyling assets
    address public escrow;

    /// @notice Whitelisted contracts that are allowed to transfer
    mapping(address => bool) public whitelisted;

    /*//////////////////////////////////////////////////////////////
                              Modifiers
    //////////////////////////////////////////////////////////////*/

    modifier onlyEscrow() {
        if (msg.sender != escrow) revert OnlyEscrow();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                ERC165
    //////////////////////////////////////////////////////////////*/

    function supportsInterface(
        bytes4 _interfaceId
    ) public view override(ERC721Enumerable) returns (bool) {
        return super.supportsInterface(_interfaceId) || _interfaceId == type(ILock).interfaceId;
    }

    /*//////////////////////////////////////////////////////////////
                              Initializer
    //////////////////////////////////////////////////////////////*/

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _escrow,
        string memory _name,
        string memory _symbol,
        address _dao
    ) external initializer {
        __ERC721_init(_name, _symbol);
        __DaoAuthorizableUpgradeable_init(IDAO(_dao));
        escrow = _escrow;

        // allow sending nfts to the escrow
        whitelisted[escrow] = true;
        emit WhitelistSet(address(this), true);
    }

    /*//////////////////////////////////////////////////////////////
                              Transfers
    //////////////////////////////////////////////////////////////*/

    /// @notice Transfers disabled by default, only whitelisted addresses can receive transfers
    function setWhitelisted(address _account, bool _isWhitelisted) external auth(LOCK_ADMIN_ROLE) {
        whitelisted[_account] = _isWhitelisted;
        emit WhitelistSet(_account, _isWhitelisted);
    }

    /// @notice Enable transfers to any address without whitelisting
    function enableTransfers() external auth(LOCK_ADMIN_ROLE) {
        whitelisted[WHITELIST_ANY_ADDRESS] = true;
        emit WhitelistSet(WHITELIST_ANY_ADDRESS, true);
    }

    /// @dev Override the transfer to check if the recipient is whitelisted
    /// This avoids needing to check for mint/burn but is less idomatic than beforeTokenTransfer
    function _transfer(address _from, address _to, uint256 _tokenId) internal override {
        if (whitelisted[WHITELIST_ANY_ADDRESS] || whitelisted[_to]) {
            super._transfer(_from, _to, _tokenId);
        } else revert NotWhitelisted();
    }

    /*//////////////////////////////////////////////////////////////
                              NFT Functions
    //////////////////////////////////////////////////////////////*/

    function isApprovedOrOwner(address _spender, uint256 _tokenId) external view returns (bool) {
        return _isApprovedOrOwner(_spender, _tokenId);
    }

    /// @notice Minting and burning functions that can only be called by the escrow contract
    function mint(address _to, uint256 _tokenId) external onlyEscrow {
        _mint(_to, _tokenId);
    }

    /// @notice Minting and burning functions that can only be called by the escrow contract
    function burn(uint256 _tokenId) external onlyEscrow {
        _burn(_tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                              UUPS Upgrade
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the address of the implementation contract in the [proxy storage slot](https://eips.ethereum.org/EIPS/eip-1967) slot the [UUPS proxy](https://eips.ethereum.org/EIPS/eip-1822) is pointing to.
    /// @return The address of the implementation contract.
    function implementation() public view returns (address) {
        return _getImplementation();
    }

    /// @notice Internal method authorizing the upgrade of the contract via the [upgradeability mechanism for UUPS proxies](https://docs.openzeppelin.com/contracts/4.x/api/proxy#UUPSUpgradeable) (see [ERC-1822](https://eips.ethereum.org/EIPS/eip-1822)).
    function _authorizeUpgrade(address) internal virtual override auth(LOCK_ADMIN_ROLE) {}
}
