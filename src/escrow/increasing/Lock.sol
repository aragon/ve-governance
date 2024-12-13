/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ILock} from "@escrow-interfaces/ILock.sol";
import {ERC721Upgradeable as ERC721} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {ERC721EnumerableUpgradeable as ERC721Enumerable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import {ERC721URIStorageUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import {ReentrancyGuardUpgradeable as ReentrancyGuard} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {DaoAuthorizableUpgradeable as DaoAuthorizable} from "@aragon/osx/core/plugin/dao-authorizable/DaoAuthorizableUpgradeable.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";

/// @title NFT representation of an escrow locking mechanism
contract Lock is
    ILock,
    ERC721Enumerable,
    UUPSUpgradeable,
    DaoAuthorizable,
    ReentrancyGuard,
    ERC721URIStorageUpgradeable
{
    /// @dev enables transfers without whitelisting
    address public constant WHITELIST_ANY_ADDRESS =
        address(uint160(uint256(keccak256("WHITELIST_ANY_ADDRESS"))));

    /// @notice role to upgrade this contract
    bytes32 public constant LOCK_ADMIN_ROLE = keccak256("LOCK_ADMIN");

    /// @notice Address of the escrow contract that holds underyling assets
    address public escrow;

    /// @notice Whitelisted contracts that are allowed to transfer
    mapping(address => bool) public whitelisted;

    string public baseTokenURI;

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
    ) public view override(ERC721Enumerable, ERC721URIStorageUpgradeable) returns (bool) {
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
        __ReentrancyGuard_init();
        escrow = _escrow;

        // allow sending nfts to the escrow
        whitelisted[escrow] = true;
        emit WhitelistSet(address(escrow), true);
    }

    /*//////////////////////////////////////////////////////////////
                              Transfers
    //////////////////////////////////////////////////////////////*/

    /// @notice Transfers disabled by default, only whitelisted addresses can receive transfers
    function setWhitelisted(address _account, bool _isWhitelisted) external auth(LOCK_ADMIN_ROLE) {
        if (_account == escrow) revert ForbiddenWhitelistAddress();
        whitelisted[_account] = _isWhitelisted;
        emit WhitelistSet(_account, _isWhitelisted);
    }

    /// @notice Enable transfers to any address without whitelisting
    function enableTransfers() external auth(LOCK_ADMIN_ROLE) {
        whitelisted[WHITELIST_ANY_ADDRESS] = true;
        emit WhitelistSet(WHITELIST_ANY_ADDRESS, true);
    }

    /// @notice Override the beforeTokenTransfer as required by ERC721Enumerable
    function _beforeTokenTransfer(
        address _from,
        address _to,
        uint256 _tokenId,
        uint256 batchSize
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(_from, _to, _tokenId, batchSize);
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
    /// @dev Safe mint ensures contract addresses are ERC721 Receiver contracts
    function mint(address _to, uint256 _tokenId) external onlyEscrow nonReentrant {
        _safeMint(_to, _tokenId);
    }

    /// @notice Minting and burning functions that can only be called by the escrow contract
    function burn(uint256 _tokenId) external onlyEscrow nonReentrant {
        _burn(_tokenId);
    }

    function _burn(uint256 _tokenId) internal override(ERC721, ERC721URIStorageUpgradeable) {
        super._burn(_tokenId);
    }

    function tokenURI(
        uint256 _tokenId
    ) public view override(ERC721, ERC721URIStorageUpgradeable) returns (string memory) {
        return super.tokenURI(_tokenId);
    }

    function _baseURI() internal view override returns (string memory) {
        return baseTokenURI;
    }

    function setBaseURI(string memory _baseTokenURI) external auth(LOCK_ADMIN_ROLE) {
        baseTokenURI = _baseTokenURI;

        emit BaseURISet(baseTokenURI);
    }

    function setTokenURI(uint256 _tokenId, string memory _tokenURI) external auth(LOCK_ADMIN_ROLE) {
        _setTokenURI(_tokenId, _tokenURI);
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

    uint256[47] private __gap;
}
