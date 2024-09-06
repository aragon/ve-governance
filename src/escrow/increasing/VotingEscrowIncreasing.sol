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
import {ReentrancyGuardUpgradeable as ReentrancyGuard} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable as Pausable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {DaoAuthorizableUpgradeable as DaoAuthorizable} from "@aragon/osx/core/plugin/dao-authorizable/DaoAuthorizableUpgradeable.sol";

// tools - delete
import {console2 as console} from "forge-std/console2.sol";

contract VotingEscrow is IVotingEscrow, ReentrancyGuard, Pausable, DaoAuthorizable, ERC721Enumerable {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    error NotImplemented();

    /// @notice Role required to manage the Escrow curve, this typically will be the DAO
    bytes32 public constant ESCROW_ADMIN_ROLE = keccak256("ESCROW_ADMIN");

    /// @notice Role required to pause the contract - can be given to emergency contracts
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /*//////////////////////////////////////////////////////////////
                              NFT Data
    //////////////////////////////////////////////////////////////*/

    /// @notice Decimals of the NFT contract
    uint8 public constant decimals = 18;

    /// @notice Autoincrementing ID of each new NFT minted
    /// @dev add to the mint function
    uint256 public tokenId;

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

    /// @notice Stores which NFTs have currently voted
    /// @dev We may replace this with a call to the voter.reset TODO
    mapping(uint256 => bool) public voted;

    /// @dev tokenId => block number of ownership change
    /// Used to prevent flash NFT explots by restricting same block actions
    /// todo check this
    mapping(uint256 => uint256) internal ownershipChange;

    /// @dev tracks the locked balance of each NFT
    mapping(uint256 => LockedBalance) internal _locked;

    /// @dev Reserved storage space to allow for layout changes in the future.
    /// TODO: move to the end of the contract once version is finalised
    uint256[40] private __gap;

    /*//////////////////////////////////////////////////////////////
                              ERC165
    //////////////////////////////////////////////////////////////*/

    // / @inheritdoc IVotingEscrow
    function supportsInterface(bytes4 _interfaceId) public view override(ERC721Enumerable) returns (bool) {
        return super.supportsInterface(_interfaceId);
    }

    /*//////////////////////////////////////////////////////////////
                              Initialization
    //////////////////////////////////////////////////////////////*/

    constructor() {
        _disableInitializers();
    }

    // todo add the initializer inheritance chain
    function initialize(address _token, address _dao, string memory _name, string memory _symbol) public initializer {
        __DaoAuthorizableUpgradeable_init(IDAO(_dao));
        __ReentrancyGuard_init();
        __Pausable_init();
        __ERC721_init(_name, _symbol);

        token = _token;

        // allow sending tokens to this contract
        whitelisted[address(this)] = true;

        // rm the zero id
        // emit Transfer(address(0), address(this), tokenId);
        // emit Transfer(address(this), address(0), tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                              Admin Setters
    //////////////////////////////////////////////////////////////*/

    /// @notice Enables or disables a smart contract from holding the veNFT
    function setWhitelisted(address _contract, bool _isWhitelisted) external auth(ESCROW_ADMIN_ROLE) {
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

    /*//////////////////////////////////////////////////////////////
                      Getters: ERC721 Functions
    //////////////////////////////////////////////////////////////*/

    function isApprovedOrOwner(address _spender, uint256 _tokenId) external view returns (bool) {
        return _isApprovedOrOwner(_spender, _tokenId);
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

    /*//////////////////////////////////////////////////////////////
                              ERC721 LOGIC
    //////////////////////////////////////////////////////////////*/

    // function _beforeTokenTransfer(address, address _to, uint256 _tokenId) internal {
    //     if (_isContract(_to) && !whitelisted[_to]) revert("Cant send to a contract"); // todo

    //     // Update voting checkpoints
    //     _checkpointDelegator(_tokenId, 0, _to);

    //     // should reset the votes if the token is transferred

    //     // reset the start date of the lock
    //     LockedBalance memory oldLocked = _locked[_tokenId];
    //     _checkpoint(_tokenId, oldLocked, LockedBalance(oldLocked.amount, block.timestamp));
    // }

    function _isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @dev Function to mint tokens
    function _mint(address _to, uint256 _tokenId) internal override {
        // // TODO Update voting checkpoints
        super._mint(_to, _tokenId);
    }

    /// @dev Must be called prior to updating `LockedBalance`
    function _burn(uint256 _tokenId) internal override {
        // // TODO Update voting checkpoints
        super._burn(_tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                              ESCROW LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Record global and per-user data to checkpoints. Used by VotingEscrow system.
    /// @param _tokenId NFT token ID. No user checkpoint if 0
    /// @param _oldLocked Pevious locked amount / end lock time for the user
    /// @param _newLocked New locked amount / end lock time for the user
    function _checkpoint(uint256 _tokenId, LockedBalance memory _oldLocked, LockedBalance memory _newLocked) internal {
        IEscrowCurve(curve).checkpoint(_tokenId, _oldLocked, _newLocked);
    }

    /// @notice Deposit and lock tokens for a user
    /// @param _tokenId NFT that holds lock
    /// @param _value Amount to deposit
    /// @param _oldLocked Previous locked amount / timestamp
    function _depositFor(uint256 _tokenId, uint256 _value, LockedBalance memory _oldLocked) internal {
        uint256 supplyBefore = totalLocked;
        totalLocked = supplyBefore + _value;

        // Set newLocked to _oldLocked without mangling memory
        LockedBalance memory newLocked;
        (newLocked.amount, newLocked.start) = (_oldLocked.amount, _oldLocked.start);

        // Adding to existing lock, or if a lock is expired - creating a new one
        // TODO new locked should probably start NOW
        newLocked.amount += _value;
        _locked[_tokenId] = newLocked;

        // Possibilities:
        // Both _oldLocked.end could be current or expired (>/< block.timestamp)
        // or if the lock is a permanent lock, then _oldLocked.end == 0
        // value == 0 (extend lock) or value > 0 (add to lock or extend lock)
        // newLocked.end > block.timestamp (always)
        _checkpoint(_tokenId, _oldLocked, newLocked);

        address from = _msgSender();
        if (_value != 0) {
            IERC20(token).safeTransferFrom(from, address(this), _value);
        }

        // todo we migth want to snap to an epoch
        emit Deposit(from, _tokenId, _value, block.timestamp);
        emit Supply(supplyBefore, supplyBefore + _value);
    }

    // / @inheritdoc IVotingEscrow
    /// TODO: quite frankly, not sure we need this
    function checkpoint() external nonReentrant {
        _checkpoint(0, LockedBalance(0, 0), LockedBalance(0, 0));
    }

    /// @dev Deposit `_value` tokens for `_to` and lock for `_lockDuration`
    /// @param _value Amount to deposit
    /// @param _to Address to deposit
    function _createLockFor(uint256 _value, address _to) internal returns (uint256) {
        // uint256 unlockTime = ((block.timestamp + _lockDuration) / EpochDurationLib.EPOCH_DURATION) *
        //     EpochDurationLib.EPOCH_DURATION; // Locktime is rounded down to weeks
        // TODO replace with starttime

        if (_value == 0) revert ZeroAmount();

        uint256 _tokenId = ++tokenId;
        _mint(_to, _tokenId);

        _depositFor(_tokenId, _value, _locked[_tokenId]);
        return _tokenId;
    }

    // / @inheritdoc IVotingEscrow
    function createLock(uint256 _value) external nonReentrant returns (uint256) {
        return _createLockFor(_value, _msgSender());
    }

    // / @inheritdoc IVotingEscrow
    function createLockFor(uint256 _value, address _to) external nonReentrant returns (uint256) {
        return _createLockFor(_value, _to);
    }

    /*//////////////////////////////////////////////////////////////
                        Exit and Withdraw Logic
    //////////////////////////////////////////////////////////////*/

    /// @notice Enters a tokenId into the withdrawal queue by transferring to this contract and creating a ticket.
    /// @param _tokenId The tokenId to begin withdrawal for. Will be transferred to this contract before burning.
    /// @dev The user must not have active votes in the voter contract.
    function beginWithdrawal(uint256 _tokenId) external nonReentrant {
        if (voted[_tokenId]) revert AlreadyVoted();
        address owner = _ownerOf(_tokenId);
        // todo: should we call queue first or second
        // todo - do we write a checkpoint here?
        _transfer(_msgSender(), address(this), _tokenId);
        IExitQueue(queue).queueExit(_tokenId, owner);
    }

    // / @inheritdoc IVotingEscrow
    // this assumes you've begun withdrawal and know the ticket ID
    function withdraw(uint256 _tokenId) external nonReentrant {
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
        _checkpoint(_tokenId, oldLocked, LockedBalance(0, block.timestamp));

        IERC20(token).safeTransfer(sender, value);

        emit Withdraw(sender, _tokenId, value, block.timestamp);
        emit Supply(supplyBefore, supplyBefore - value);
    }

    /*//////////////////////////////////////////////////////////////
                        Voting Logic
    //////////////////////////////////////////////////////////////*/

    function isVoting(uint256 _tokenId) external view returns (bool) {
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

    function getPastVotes(address _account, uint256 _tokenId, uint256 _timestamp) external view returns (uint256) {
        revert NotImplemented();
    }

    function getPastTotalSupply(uint256 _timestamp) external view returns (uint256) {
        return totalVotingPowerAt(_timestamp);
    }
}
