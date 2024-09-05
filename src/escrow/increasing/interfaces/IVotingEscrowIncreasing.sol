// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC165, IERC721, IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";
import {IERC4906} from "@openzeppelin/contracts/interfaces/IERC4906.sol";
import {IVotes} from "./IVotes.sol";

/*///////////////////////////////////////////////////////////////
                        CORE FUNCTIONALITY
//////////////////////////////////////////////////////////////*/

interface ILockedBalanceIncreasing {
    struct LockedBalance {
        uint256 amount;
        uint256 start;
    }
}

interface IVotingEscrowCoreErrors {
    error NoLockFound();
    error NotOwner();
    error NonExistentToken();
    error NotApprovedOrOwner();
    error ZeroAddress();
    error ZeroAmount();
    error ZeroBalance();
    error SameAddress();
}

interface IVotingEscrowCoreEvents {
    event Deposit(address indexed depositor, uint256 indexed tokenId, uint256 value, uint256 ts);
    event Withdraw(address indexed depositor, uint256 indexed tokenId, uint256 value, uint256 ts);
    event Supply(uint256 prevSupply, uint256 supply);
}

interface IVotingEscrowCore is ILockedBalanceIncreasing, IVotingEscrowCoreErrors, IVotingEscrowCoreEvents {
    /// @notice Address of the underying ERC20 token.
    function token() external view returns (address);

    /// @notice Autoincrementing ID of each new NFT minted
    function tokenId() external view returns (uint256);

    /// @notice Total underlying tokens deposited in the contract
    function totalLocked() external view returns (uint256);

    /// @notice Get the raw locked balance for `_tokenId`
    function locked(uint256 _tokenId) external view returns (LockedBalance memory);

    /// @notice Deposit `_value` tokens for `msg.sender`
    /// @param _value Amount to deposit
    /// @return TokenId of created veNFT
    function createLock(uint256 _value) external returns (uint256);

    /// @notice Deposit `_value` tokens for `_to`
    /// @param _value Amount to deposit
    /// @param _to Address to deposit
    /// @return TokenId of created veNFT
    function createLockFor(uint256 _value, address _to) external returns (uint256);

    /// @notice Withdraw all tokens for `_tokenId`
    /// @dev Only possible if the lock is both expired and not permanent
    ///      This will burn the veNFT. Any rebases or rewards that are unclaimed
    ///      will no longer be claimable. Claim all rebases and rewards prior to calling this.
    function withdraw(uint256 _tokenId) external;

    // TODO - this is nonstandard and used heavily - is there a better public function here that's more standardised
    function isApprovedOrOwner(address spender, uint256 tokenId) external view returns (bool);
}

/*///////////////////////////////////////////////////////////////
                        WHITELIST ESCROW
//////////////////////////////////////////////////////////////*/
interface IWhitelistEvents {
    event WhitelistSet(address indexed account, bool status);
}

interface IWhitelist is IWhitelistEvents {
    /// @notice Set whitelist status for an address
    /// Typically used to prevent unknown smart contracts from interacting with the system
    function setWhitelisted(address addr, bool isWhitelisted) external;

    /// @notice Check if an address is whitelisted
    function whitelisted(address addr) external view returns (bool);
}

/*///////////////////////////////////////////////////////////////
                        WITHDRAWAL QUEUE
//////////////////////////////////////////////////////////////*/

interface IWithdrawalQueueErrors {
    error NotTicketHolder();
    error CannotExit();
}

interface IWithdrawalQueueEvents {}

interface IWithdrawalQueue is IWithdrawalQueueErrors, IWithdrawalQueueEvents {
    /// @notice Enters a tokenId into the withdrawal queue by transferring to this contract and creating a ticket.
    /// @param _tokenId The tokenId to begin withdrawal for. Will be transferred to this contract before burning.
    /// @dev The user must not have active votes in the voter contract.
    function beginWithdrawal(uint256 _tokenId) external;

    /// @notice Address of the contract that manages exit queue logic for withdrawals
    function queue() external view returns (address);
}

/*///////////////////////////////////////////////////////////////
                        DYNAMIC VOTER
//////////////////////////////////////////////////////////////*/

interface IDynamicVoterErrors {
    error NotVoter();
    error OwnershipChange();
    error AlreadyVoted();
}

interface IDynamicVoter is IDynamicVoterErrors {
    /// @notice Address of the voting contract.
    /// @dev We need to ensure votes are not left in this contract before allowing positing changes
    function voter() external view returns (address);

    /// @notice Address of the voting Escrow Curve contract that will calculate the voting power
    function curve() external view returns (address);

    /// @notice Get the voting power for _tokenId at the current timestamp
    /// @dev Returns 0 if called in the same block as a transfer.
    /// @param _tokenId .
    /// @return Voting power
    function votingPower(uint256 _tokenId) external view returns (uint256);

    /// @notice Get the voting power for _tokenId at a given timestamp
    /// @param _tokenId .
    /// @param _t Timestamp to query voting power
    /// @return Voting power
    function votingPowerAt(uint256 _tokenId, uint256 _t) external view returns (uint256);

    /// @notice Calculate total voting power at current timestamp
    /// @return Total voting power at current timestamp
    function totalVotingPower() external view returns (uint256);

    /// @notice Calculate total voting power at a given timestamp
    /// @param _t Timestamp to query total voting power
    /// @return Total voting power at given timestamp
    function totalVotingPowerAt(uint256 _t) external view returns (uint256);

    /// @notice See if a queried _tokenId has actively voted
    /// @return True if voted, else false
    function isVoting(uint256 _tokenId) external view returns (bool);

    /// @notice Set the global state voter
    function setVoter(address _voter) external;
}

/*///////////////////////////////////////////////////////////////
                        INCREASED ESCROW
//////////////////////////////////////////////////////////////*/

interface IVotingEscrowIncreasing is IVotingEscrowCore, IDynamicVoter, IWithdrawalQueue, IWhitelist {

}