/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

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
    error LockNFTAlreadySet();
    error MustBe18Decimals();
}

interface IVotingEscrowCoreEvents {
    event Deposit(
        address indexed depositor,
        uint256 indexed tokenId,
        uint256 indexed startTs,
        uint256 value,
        uint256 newTotalLocked
    );
    event Withdraw(
        address indexed depositor,
        uint256 indexed tokenId,
        uint256 value,
        uint256 ts,
        uint256 newTotalLocked
    );
}

interface IVotingEscrowCore is
    ILockedBalanceIncreasing,
    IVotingEscrowCoreErrors,
    IVotingEscrowCoreEvents
{
    /// @notice Address of the underying ERC20 token.
    function token() external view returns (address);

    /// @notice Address of the lock receipt NFT.
    function lockNFT() external view returns (address);

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
    function withdraw(uint256 _tokenId) external;

    /// @notice helper utility for NFT checks
    function isApprovedOrOwner(address spender, uint256 tokenId) external view returns (bool);
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
                        SWEEPER
//////////////////////////////////////////////////////////////*/

interface ISweeperEvents {
    event Sweep(address indexed to, uint256 amount);
    event SweepNFT(address indexed to, uint256 tokenId);
}

interface ISweeperErrors {
    error NothingToSweep();
}

interface ISweeper is ISweeperEvents, ISweeperErrors {
    /// @notice sweeps excess tokens from the contract to a designated address
    function sweep() external;

    function sweepNFT(uint256 _tokenId, address _to) external;
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

    /// @notice Get the voting power for _account at the current timestamp
    /// Aggregtes all voting power for all tokens owned by the account
    /// @dev This cannot be used historically without token snapshots
    function votingPowerForAccount(address _account) external view returns (uint256);

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

interface IVotingEscrowIncreasing is IVotingEscrowCore, IDynamicVoter, IWithdrawalQueue, ISweeper {

}

/// @dev useful for testing
interface IVotingEscrowEventsStorageErrorsEvents is
    IVotingEscrowCoreErrors,
    IVotingEscrowCoreEvents,
    IWithdrawalQueueErrors,
    IWithdrawalQueueEvents,
    ILockedBalanceIncreasing,
    ISweeperEvents,
    ISweeperErrors
{

}
