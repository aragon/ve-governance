/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// token interfaces
import {IERC20Upgradeable as IERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IERC20MetadataUpgradeable as IERC20Metadata} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {IERC721EnumerableMintableBurnable as IERC721EMB} from "./interfaces/IERC721EMB.sol";

// veGovernance
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {ISimpleGaugeVoter} from "@voting/ISimpleGaugeVoter.sol";
import {IClock} from "@clock/IClock.sol";
import {IEscrowCurveIncreasing as IEscrowCurve} from "./interfaces/IEscrowCurveIncreasing.sol";
import {IExitQueue} from "./interfaces/IExitQueue.sol";
import {IVotingEscrowIncreasing as IVotingEscrow} from "./interfaces/IVotingEscrowIncreasing.sol";

// libraries
import {SafeERC20Upgradeable as SafeERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {SafeCastUpgradeable as SafeCast} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

// parents
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable as ReentrancyGuard} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable as Pausable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {DaoAuthorizableUpgradeable as DaoAuthorizable} from "@aragon/osx/core/plugin/dao-authorizable/DaoAuthorizableUpgradeable.sol";

contract VotingEscrow is
    IVotingEscrow,
    ReentrancyGuard,
    Pausable,
    DaoAuthorizable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    /// @notice Role required to manage the Escrow curve, this typically will be the DAO
    bytes32 public constant ESCROW_ADMIN_ROLE = keccak256("ESCROW_ADMIN");

    /// @notice Role required to pause the contract - can be given to emergency contracts
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER");

    /// @notice Role required to withdraw underlying tokens from the contract
    bytes32 public constant SWEEPER_ROLE = keccak256("SWEEPER");

    /*//////////////////////////////////////////////////////////////
                              NFT Data
    //////////////////////////////////////////////////////////////*/

    /// @notice Total supply of underlying tokens deposited in the contract
    uint256 public totalLocked;

    /// @dev tracks the locked balance of each NFT
    mapping(uint256 => LockedBalance) private _locked;

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

    /// @notice Address of the clock contract that manages epoch and voting periods
    address public clock;

    /// @notice Address of the NFT contract that is the lock
    address public lockNFT;

    /*//////////////////////////////////////////////////////////////
                              Initialization
    //////////////////////////////////////////////////////////////*/

    constructor() {
        _disableInitializers();
    }

    function initialize(address _token, address _dao, address _clock) external initializer {
        __DaoAuthorizableUpgradeable_init(IDAO(_dao));
        __ReentrancyGuard_init();
        __Pausable_init();

        token = _token;
        clock = _clock;
    }

    /*//////////////////////////////////////////////////////////////
                              Admin Setters
    //////////////////////////////////////////////////////////////*/

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

    /// @notice Sets the clock contract that manages epoch and voting periods
    function setClock(address _clock) external auth(ESCROW_ADMIN_ROLE) {
        clock = _clock;
    }

    function setLockNFT(address _nft) external auth(ESCROW_ADMIN_ROLE) {
        lockNFT = _nft;
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
        return IERC721EMB(lockNFT).isApprovedOrOwner(_spender, _tokenId);
    }

    /// @notice Fetch all NFTs owned by an address by leveraging the ERC721Enumerable interface
    /// @param _owner Address to query
    /// @return tokenIds Array of token IDs owned by the address
    function ownedTokens(address _owner) public view returns (uint256[] memory tokenIds) {
        IERC721EMB enumerable = IERC721EMB(lockNFT);
        uint256 balance = enumerable.balanceOf(_owner);
        uint256[] memory tokens = new uint256[](balance);
        for (uint256 i = 0; i < balance; i++) {
            tokens[i] = enumerable.tokenOfOwnerByIndex(_owner, i);
        }
        return tokens;
    }

    /*///////////////////////////////////////////////////////////////
                          Getters: Voting
    //////////////////////////////////////////////////////////////*/

    /// @return The voting power of the NFT at the current block
    function votingPower(uint256 _tokenId) public view returns (uint256) {
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

    /// @notice Checks if the NFT is currently voting. We require the user to reset their votes if so.
    function isVoting(uint256 _tokenId) public view returns (bool) {
        return ISimpleGaugeVoter(voter).isVoting(_tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                              ESCROW LOGIC
    //////////////////////////////////////////////////////////////*/

    function createLock(uint256 _value) external nonReentrant whenNotPaused returns (uint256) {
        return _createLockFor(_value, _msgSender());
    }

    /// @notice Creates a lock on behalf of someone else. Restricted by default.
    function createLockFor(
        uint256 _value,
        address _to
    ) external nonReentrant whenNotPaused returns (uint256) {
        return _createLockFor(_value, _to);
    }

    /// @dev Deposit `_value` tokens for `_to` starting at next deposit interval
    /// @param _value Amount to deposit
    /// @param _to Address to deposit
    function _createLockFor(uint256 _value, address _to) internal returns (uint256) {
        if (_value == 0) revert ZeroAmount();

        // query the duration lib to get the next time we can deposit
        uint256 startTime = IClock(clock).epochNextCheckpointTs();

        // increment the total locked supply and get the new tokenId
        totalLocked += _value;
        uint256 newTokenId = IERC721EMB(lockNFT).totalSupply() + 1;

        // write the lock and checkpoint the voting power
        LockedBalance memory lock = LockedBalance(_value, startTime);
        _locked[newTokenId] = lock;

        // we don't allow edits in this implementation, so only the new lock is used
        _checkpoint(newTokenId, lock);

        // transfer the tokens into the contract
        IERC20(token).safeTransferFrom(_msgSender(), address(this), _value);

        // mint the NFT to complete the deposit
        IERC721EMB(lockNFT).mint(_to, newTokenId);
        emit Deposit(_to, newTokenId, startTime, _value, totalLocked);

        return newTokenId;
    }

    /// @notice Record per-user data to checkpoints. Used by VotingEscrow system.
    /// @param _tokenId NFT token ID
    /// @dev Old locked balance is unused in the increasing case, at least in this implementation
    /// @param _newLocked New locked amount / start lock time for the user
    function _checkpoint(uint256 _tokenId, LockedBalance memory _newLocked) private {
        IEscrowCurve(curve).checkpoint(_tokenId, LockedBalance(0, 0), _newLocked);
    }

    /// @dev resets the voting power for a given tokenId. Checkpoint is written to the end of the epoch.
    /// @param _tokenId The tokenId to reset the voting power for
    /// @dev We don't need to fetch the old locked balance as it's not used in this implementation
    function _checkpointClear(uint256 _tokenId) private {
        uint256 checkpointClearTime = IClock(clock).epochNextCheckpointTs();
        IEscrowCurve(curve).checkpoint(
            _tokenId,
            LockedBalance(0, 0),
            LockedBalance(0, checkpointClearTime)
        );
    }

    /*//////////////////////////////////////////////////////////////
                        Exit and Withdraw Logic
    //////////////////////////////////////////////////////////////*/

    /// @notice Resets the votes and begins the withdrawal process for a given tokenId
    /// @dev Convenience function, the user must have authorized this contract to act on their behalf.
    function resetVotesAndBeginWithdrawal(uint256 _tokenId) external whenNotPaused {
        ISimpleGaugeVoter(voter).reset(_tokenId);
        beginWithdrawal(_tokenId);
    }

    /// @notice Enters a tokenId into the withdrawal queue by transferring to this contract and creating a ticket.
    /// @param _tokenId The tokenId to begin withdrawal for. Will be transferred to this contract before burning.
    /// @dev The user must not have active votes in the voter contract.
    function beginWithdrawal(uint256 _tokenId) public nonReentrant whenNotPaused {
        // can't exit if you have votes pending
        if (isVoting(_tokenId)) revert CannotExit();

        address owner = IERC721EMB(lockNFT).ownerOf(_tokenId);

        // we can remove the user's voting power as it's no longer locked
        _checkpointClear(_tokenId);

        // transfer NFT to this and queue the exit
        IERC721EMB(lockNFT).transferFrom(_msgSender(), address(this), _tokenId);
        IExitQueue(queue).queueExit(_tokenId, owner);
    }

    /// @notice Withdraws tokens from the contract
    function withdraw(uint256 _tokenId) external nonReentrant whenNotPaused {
        address sender = _msgSender();

        // we force the sender to be the ticket holder
        if (!(IExitQueue(queue).ticketHolder(_tokenId) == sender)) revert NotTicketHolder();

        // check that this ticket can exit
        if (!(IExitQueue(queue).canExit(_tokenId))) revert CannotExit();

        LockedBalance memory oldLocked = _locked[_tokenId];
        uint256 value = oldLocked.amount;

        // check for fees to be transferred
        // do this before clearing the lock or it will be incorrect
        uint256 fee = IExitQueue(queue).exit(_tokenId);
        if (fee > 0) {
            IERC20(token).safeTransfer(address(queue), fee);
        }

        // clear out the token data
        _locked[_tokenId] = LockedBalance(0, 0);
        totalLocked -= value;

        // Burn the NFT and transfer the tokens to the user
        IERC721EMB(lockNFT).burn(_tokenId);
        IERC20(token).safeTransfer(sender, value - fee);

        emit Withdraw(sender, _tokenId, value - fee, block.timestamp, totalLocked);
    }

    /// @notice withdraw excess tokens from the contract - possibly by accident
    function sweep() external nonReentrant auth(SWEEPER_ROLE) {
        // if there are extra tokens in the contract
        // balance will be greater than the total locked
        uint balance = IERC20(token).balanceOf(address(this));
        uint excess = balance - totalLocked;

        // if there isn't revert the tx
        if (excess == 0) revert NothingToSweep();

        // if there is, send them to the caller
        IERC20(token).safeTransfer(_msgSender(), excess);
        emit Sweep(_msgSender(), excess);
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

    /// @dev Reserved storage space to allow for layout changes in the future.
    uint256[42] private __gap;
}
