// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.17;

// token interfaces
import {IERC20Upgradeable as IERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IERC721Upgradeable as IERC721, ERC721Upgradeable as ERC721} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {IERC721MetadataUpgradeable as IERC721Metadata} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/IERC721MetadataUpgradeable.sol";
import {ERC721EnumerableUpgradeable as ERC721Enumerable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";

// veGovernance
import {IEscrowCurveIncreasing as IEscrowCurve} from "./interfaces/IEscrowCurveIncreasing.sol";
import {IExitQueue} from "./interfaces/IExitQueue.sol";
import {IVotingEscrowIncreasing as IVotingEscrow, ILockedBalanceIncreasing, IVotingEscrowCore, IDynamicVoter} from "./interfaces/IVotingEscrowIncreasing.sol";
import {ISimpleGaugeVoter} from "../../voting/ISimpleGaugeVoter.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";

// libraries
import {SafeERC20Upgradeable as SafeERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {SafeCastUpgradeable as SafeCast} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {EpochDurationLib} from "@libs/EpochDurationLib.sol";

// parents
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable as ReentrancyGuard} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable as Pausable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {DaoAuthorizableUpgradeable as DaoAuthorizable} from "@aragon/osx/core/plugin/dao-authorizable/DaoAuthorizableUpgradeable.sol";

// tools - delete
import {console2 as console} from "forge-std/console2.sol";

contract VotingEscrow is
    IVotingEscrow,
    ReentrancyGuard,
    Pausable,
    DaoAuthorizable,
    ERC721Enumerable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    error NotImplemented();

    /// @notice Role required to manage the Escrow curve, this typically will be the DAO
    bytes32 public constant ESCROW_ADMIN_ROLE = keccak256("ESCROW_ADMIN");

    /// @notice Role required to pause the contract - can be given to emergency contracts
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER");

    /// @notice creating locks on behalf of others is potentially dangerous
    bytes32 public constant LOCK_CREATOR_ROLE = keccak256("LOCK_CREATOR");

    /*//////////////////////////////////////////////////////////////
                              NFT Data
    //////////////////////////////////////////////////////////////*/

    /// @notice Decimals of the voting power
    /// TODO: validate tokens with nonstandard decimals
    uint8 public constant decimals = 18;

    /// @notice Total supply of underlying tokens deposited in the contract
    uint256 public totalLocked;

    /*//////////////////////////////////////////////////////////////
                              Helper Contracts
    //////////////////////////////////////////////////////////////*/

    /// @notice Address of the underying ERC20 token.
    address public token;

    /// @notice Address of the gauge voting contract.
    /// @dev We need to ensure votes are not left in this contract before allowing positing changes
    address public voter;

    /// @notice Address of the voting Escrow Curve contract that will calculate the voting power
    address public curve;

    /// @notice Address of the contract that manages exit queue logic for withdrawals
    address public queue;

    /*//////////////////////////////////////////////////////////////
                              Mappings
    //////////////////////////////////////////////////////////////*/

    /// @notice Whitelisted contracts that can hold the NFT
    /// @dev discourages wrapper contracts that would allow for trading voting power
    mapping(address => bool) public whitelisted;

    /// @dev tokenId => block number of ownership change
    /// Used to prevent flash NFT explots by restricting same block actions
    /// todo check this
    mapping(uint256 => uint256) internal ownershipChange;

    /// @dev tracks the locked balance of each NFT
    mapping(uint256 => LockedBalance) internal _locked;

    /// @dev Reserved storage space to allow for layout changes in the future.
    uint256[42] private __gap;

    /*//////////////////////////////////////////////////////////////
                              ERC165
    //////////////////////////////////////////////////////////////*/

    // / @inheritdoc IVotingEscrow
    function supportsInterface(
        bytes4 _interfaceId
    ) public view override(ERC721Enumerable) returns (bool) {
        return super.supportsInterface(_interfaceId);
    }

    /*//////////////////////////////////////////////////////////////
                              Initialization
    //////////////////////////////////////////////////////////////*/

    constructor() {
        _disableInitializers();
    }

    // todo add the initializer inheritance chain
    function initialize(
        address _token,
        address _dao,
        string memory _name,
        string memory _symbol
    ) external initializer {
        __DaoAuthorizableUpgradeable_init(IDAO(_dao));
        __ReentrancyGuard_init();
        __Pausable_init();
        __ERC721_init(_name, _symbol);

        token = _token;

        // allow sending tokens to this contract
        whitelisted[address(this)] = true;
        emit WhitelistSet(address(this), true);

        // rm the zero id
        // emit Transfer(address(0), address(this), tokenId);
        // emit Transfer(address(this), address(0), tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                              Admin Setters
    //////////////////////////////////////////////////////////////*/

    /// @notice Enables or disables a smart contract from holding the veNFT
    function setWhitelisted(
        address _contract,
        bool _isWhitelisted
    ) external auth(ESCROW_ADMIN_ROLE) {
        whitelisted[_contract] = _isWhitelisted;
        emit WhitelistSet(_contract, _isWhitelisted);
    }

    /// @notice Sets the curve contract that calculates the voting power
    function setCurve(address _curve) external auth(ESCROW_ADMIN_ROLE) {
        curve = _curve;
    }

    /// @notice Sets the voter contract that tracks votes
    function setVoter(address _voter) external auth(ESCROW_ADMIN_ROLE) {
        voter = _voter;
    }

    /// @notice Sets the exit queue contract that manages withdrawal eligibility
    function setQueue(address _queue) external auth(ESCROW_ADMIN_ROLE) {
        queue = _queue;
    }

    function pause() external auth(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external auth(PAUSER_ROLE) {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                      Getters: ERC721 Functions
    //////////////////////////////////////////////////////////////*/

    function isApprovedOrOwner(address _spender, uint256 _tokenId) external view returns (bool) {
        return _isApprovedOrOwner(_spender, _tokenId);
    }

    /// @notice Fetch all NFTs owned by an address by leveraging the ERC721Enumerable interface
    /// @param _owner Address to query
    /// @return tokenIds Array of token IDs owned by the address
    function ownedTokens(address _owner) public view returns (uint256[] memory tokenIds) {
        uint256 balance = balanceOf(_owner);
        uint256[] memory tokens = new uint256[](balance);
        for (uint256 i = 0; i < balance; i++) {
            tokens[i] = tokenOfOwnerByIndex(_owner, i);
        }
        return tokens;
    }

    /*///////////////////////////////////////////////////////////////
                          Getters: Voting Power
    //////////////////////////////////////////////////////////////*/

    /// @return The voting power of the NFT at the current block
    function votingPower(uint256 _tokenId) public view returns (uint256) {
        // if (ownershipChange[_tokenId] == block.number) return 0;
        return votingPowerAt(_tokenId, block.timestamp);
    }

    /// @return The voting power of the NFT at a specific timestamp
    function votingPowerAt(uint256 _tokenId, uint256 _t) public view returns (uint256) {
        return IEscrowCurve(curve).votingPowerAt(_tokenId, _t);
    }

    /// @return The total voting power at the current block
    /// @dev Currently unsupported
    function totalVotingPower() external view returns (uint256) {
        return totalVotingPowerAt(block.timestamp);
    }

    /// @return The total voting power at a specific timestamp
    /// @dev Currently unsupported
    function totalVotingPowerAt(uint256 _timestamp) public view returns (uint256) {
        return IEscrowCurve(curve).supplyAt(_timestamp);
    }

    /// @return The details of the underlying lock for a given veNFT
    function locked(uint256 _tokenId) external view returns (LockedBalance memory) {
        return _locked[_tokenId];
    }

    /// @return accountVotingPower The voting power of an account at the current block
    /// @dev We cannot do historic voting power at this time because we don't current track
    /// histories of token transfers.
    function votingPowerForAccount(
        address _account
    ) external view returns (uint256 accountVotingPower) {
        uint256[] memory tokens = ownedTokens(_account);

        for (uint256 i = 0; i < tokens.length; i++) {
            accountVotingPower += votingPowerAt(tokens[i], block.timestamp);
        }
    }

    /*//////////////////////////////////////////////////////////////
                              ERC721 LOGIC
    //////////////////////////////////////////////////////////////*/

    error NotWhitelistedForTransfers();

    /// @dev This is an option and might be a sane default for a lock.
    /// @dev We could allow transfers for whitelisted accounts. This would allow
    /// for migrations, authorised wrapper contracts and the like
    function _transfer(address _from, address _to, uint256 _tokenId) internal override {
        // if (!whitelisted[_to]) revert NotWhitelistedForTransfers();
        super._transfer(_from, _to, _tokenId);
    }

    function _beforeTokenTransfer(
        address _from,
        address _to,
        uint256 _tokenId,
        uint256 _batchSize
    ) internal override {
        super._beforeTokenTransfer(_from, _to, _tokenId, _batchSize);

        // if (_isContract(_to) && !whitelisted[_to]) revert("Cant send to a contract"); // todo
        // should reset the votes if the token is transferred
        // reset the start date of the lock - we need to be careful how this interplays with mint
        // we also need to restart voting power at the next epoch
        // LockedBalance memory oldLocked = _locked[_tokenId];
        // _checkpoint(_tokenId, oldLocked, LockedBalance(oldLocked.amount, block.timestamp));
    }

    function _isContract(address _account) internal view returns (bool) {
        // This method relies on extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.
        uint256 size;
        assembly {
            size := extcodesize(_account)
        }
        return size > 0;
    }

    /// @dev This checks to see if the transaction originated from the caller
    /// TODO: placing restrictions using this method restricts use of the plugin to EOAs
    /// which goes against utility of smart wallets etc. We need to think deeply about this.
    function _isEOA() internal view returns (bool) {
        return msg.sender == tx.origin;
    }

    /*//////////////////////////////////////////////////////////////
                              ESCROW LOGIC
    //////////////////////////////////////////////////////////////*/

    function createLock(uint256 _value) external nonReentrant whenNotPaused returns (uint256) {
        return _createLockFor(_value, _msgSender());
    }

    /// @notice Creates a lock on behalf of someone else. This is restricted by default as
    /// can lead to circumventions of restrictions surrounding smart contract wallets.
    function createLockFor(
        uint256 _value,
        address _to
    ) external nonReentrant whenNotPaused returns (/* auth(LOCK_CREATOR_ROLE) */ uint256) {
        return _createLockFor(_value, _to);
    }

    /// @dev Deposit `_value` tokens for `_to` starting at next deposit interval
    /// @param _value Amount to deposit
    /// @param _to Address to deposit
    function _createLockFor(uint256 _value, address _to) internal returns (uint256) {
        if (_value == 0) revert ZeroAmount();

        // query the duration lib to get the next time we can deposit
        uint256 startTime = EpochDurationLib.epochNextDeposit(block.timestamp);

        // increment the total locked supply and mint the token
        totalLocked += _value;
        uint256 newTokenId = totalSupply() + 1;
        _mint(_to, newTokenId);

        // write the lock and checkpoint the voting power
        LockedBalance memory lock = LockedBalance(_value, startTime);
        _locked[newTokenId] = lock;

        // write the checkpoint with the old lock as 0
        // TODO: maybe this could be added to mint?
        _checkpoint(newTokenId, LockedBalance(0, 0), lock);

        // transfer the tokens into the contract
        IERC20(token).safeTransferFrom(_msgSender(), address(this), _value);
        emit Deposit(_to, newTokenId, startTime, _value, totalLocked);

        return newTokenId;
    }

    /// @notice Record per-user data to checkpoints. Used by VotingEscrow system.
    /// @param _tokenId NFT token ID
    /// @param _oldLocked Old locked amount / start lock time for the user
    /// @param _newLocked New locked amount / start lock time for the user
    function _checkpoint(
        uint256 _tokenId,
        LockedBalance memory _oldLocked,
        LockedBalance memory _newLocked
    ) internal {
        IEscrowCurve(curve).checkpoint(_tokenId, _oldLocked, _newLocked);
    }

    /*//////////////////////////////////////////////////////////////
                        Exit and Withdraw Logic
    //////////////////////////////////////////////////////////////*/

    /// @notice Enters a tokenId into the withdrawal queue by transferring to this contract and creating a ticket.
    /// @param _tokenId The tokenId to begin withdrawal for. Will be transferred to this contract before burning.
    /// @dev The user must not have active votes in the voter contract.
    function beginWithdrawal(uint256 _tokenId) external nonReentrant whenNotPaused {
        // can't exit if you have votes pending
        // TODO: UX we could simplify by attempting to withdraw
        if (isVoting(_tokenId)) revert CannotExit();
        address owner = _ownerOf(_tokenId);
        // todo: should we call queue first or second
        // todo - do we write a checkpoint here?
        _transfer(_msgSender(), address(this), _tokenId);
        IExitQueue(queue).queueExit(_tokenId, owner);
    }

    // this assumes you've begun withdrawal and know the ticket ID
    function withdraw(uint256 _tokenId) external nonReentrant whenNotPaused {
        address sender = _msgSender();

        if (!(IExitQueue(queue).ticketHolder(_tokenId) == sender)) revert NotTicketHolder();
        if (!(IExitQueue(queue).canExit(_tokenId))) revert CannotExit();

        LockedBalance memory oldLocked = _locked[_tokenId];
        uint256 value = oldLocked.amount;

        // Burn the NFT
        _burn(_tokenId); // todo: at the moment this doesn't like that the contract owns the token
        _locked[_tokenId] = LockedBalance(0, 0);
        uint256 supplyBefore = totalLocked;
        totalLocked = supplyBefore - value;

        // oldLocked can have either expired <= timestamp or zero end
        // oldLocked has only 0 end
        // Both can have >= 0 amount
        // TODO: we need to reset the locked balance here, not have it lingering
        _checkpoint(_tokenId, oldLocked, LockedBalance(0, 0));

        IERC20(token).safeTransfer(sender, value);

        emit Withdraw(sender, _tokenId, value, block.timestamp, totalLocked);
    }

    /*//////////////////////////////////////////////////////////////
                        Voting Logic
    //////////////////////////////////////////////////////////////*/

    function isVoting(uint256 _tokenId) public view returns (bool) {
        return ISimpleGaugeVoter(voter).isVoting(_tokenId);
    }

    /*///////////////////////////////////////////////////////////////
                            IVotes Ideas
    //////////////////////////////////////////////////////////////*/

    // TODO - let's check delegation in depth to see if this iface makes sense

    function getVotes(uint256 _tokenId) external view returns (uint256) {
        return votingPowerAt(_tokenId, block.timestamp);
    }

    function getVotes(address _account, uint256 _tokenId) external view returns (uint256) {
        if (_ownerOf(_tokenId) != _account) return 0;
        return votingPowerAt(_tokenId, block.timestamp);
    }

    function getPastVotes(uint256 _tokenId, uint256 _timestamp) external view returns (uint256) {
        return votingPowerAt(_tokenId, _timestamp);
    }

    function getPastVotes(
        address _account,
        uint256 _tokenId,
        uint256 _timestamp
    ) external view returns (uint256) {
        revert NotImplemented();
    }

    function getPastTotalSupply(uint256 _timestamp) external view returns (uint256) {
        return totalVotingPowerAt(_timestamp);
    }

    /*///////////////////////////////////////////////////////////////
                            UUPS Upgrade
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the address of the implementation contract in the [proxy storage slot](https://eips.ethereum.org/EIPS/eip-1967) slot the [UUPS proxy](https://eips.ethereum.org/EIPS/eip-1822) is pointing to.
    /// @return The address of the implementation contract.
    function implementation() public view returns (address) {
        return _getImplementation();
    }

    /// @notice Internal method authorizing the upgrade of the contract via the [upgradeability mechanism for UUPS proxies](https://docs.openzeppelin.com/contracts/4.x/api/proxy#UUPSUpgradeable) (see [ERC-1822](https://eips.ethereum.org/EIPS/eip-1822)).
    function _authorizeUpgrade(address) internal virtual override auth(ESCROW_ADMIN_ROLE) {}
}
