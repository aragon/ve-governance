/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IVotingEscrowIncreasingV1_4_0 as IVotingEscrow} from "@escrow/IVotingEscrowIncreasing_v1_4_0.sol";

import {IClockUser} from "@clock/IClock.sol";
import {IClockSeason} from "@clock/IClockSeason.sol";

import {ReentrancyGuardUpgradeable as ReentrancyGuard} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PluginUUPSUpgradeable} from "@aragon/osx/core/plugin/PluginUUPSUpgradeable.sol";
import {IVotes, IDelegationMapper} from "./IDelegationMapper.sol";
import {MathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {console2 as console} from "forge-std/console2.sol";

contract DelegationMapper is
    IClockUser,
    ReentrancyGuard,
    IDelegationMapper,
    IVotes,
    PluginUUPSUpgradeable
{
    using SafeCastUpgradeable for uint256;

    /// @notice Address of the voting escrow contract that will track voting power
    address public escrow;

    /// @notice Clock contract for epoch duration
    address public clock;

    struct DelegateCheckpoint {
        address delegatee;
        uint32 timestamp;
    }

    struct BalanceCheckpoint {
        uint224 balance;
        uint32 timestamp;
    }

    mapping(uint256 => DelegateCheckpoint[]) private delegationCheckpoints;
    mapping(address => BalanceCheckpoint[]) private balanceCheckpoints;

    error NotApprovedOrOwner();
    error CanNotDelegateeToAddressZero();
    error CanNotDelegateToSameAddress();
    error TokenNotDelegated(uint256 tokenId);
    error InvalidPullTimestamp();

    /*///////////////////////////////////////////////////////////////
                            Initialization
    //////////////////////////////////////////////////////////////*/

    constructor() {
        _disableInitializers();
    }

    function initialize(address _dao, address _escrow, address _clock) external initializer {
        __PluginUUPSUpgradeable_init(IDAO(_dao));
        __ReentrancyGuard_init();
        escrow = _escrow;
        clock = _clock;
    }

    // Called by the delegator..
    function delegate(uint256[] calldata _tokenIds, address _to) public {
        if (_to == address(0)) {
            revert CanNotDelegateeToAddressZero();
        }

        address sender = _msgSender();

        uint256 add = 0;
        uint256 subtract = 0;

        for (uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 tokenId = _tokenIds[i];

            // ensure the sender owns the `tokenId`.
            if (!IVotingEscrow(escrow).isApprovedOrOwner(sender, tokenId)) {
                revert NotApprovedOrOwner();
            }

            (address currentDelegatee, uint32 ts) = getDelegate(tokenId, block.timestamp);

            // revert in case user tries to delegate to the same address as before.
            if (currentDelegatee == _to) {
                revert CanNotDelegateToSameAddress();
            }

            uint256 newVotingPower = getVP(tokenId, block.timestamp);

            add += newVotingPower;

            // delegate changes, so reduce old delegatee's balance.
            if (currentDelegatee != address(0)) {
                _updateLatestBalance(currentDelegatee, getVP(tokenId, ts), 0);
            }

            _updateLatestDelegate(tokenId, _to);
        }

        _updateLatestBalance(_to, subtract, add);
    }

    function undelegate(uint256[] calldata _tokenIds) public {
        address sender = _msgSender();
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 tokenId = _tokenIds[i];

            // ensure the sender owns the `tokenId`.
            if (!IVotingEscrow(escrow).isApprovedOrOwner(sender, tokenId)) {
                revert NotApprovedOrOwner();
            }

            (address currentDelegatee, uint32 ts) = getDelegate(tokenId, block.timestamp);

            _updateLatestBalance(currentDelegatee, getVP(tokenId, ts), 0);
            _updateLatestDelegate(tokenId, address(0));
        }
    }

    // Called by delegatee to re-pull the power and update its power.
    function pull(uint256[] calldata _tokenIds, uint256 _timestamp) public {
        if (_timestamp > block.timestamp) {
            revert InvalidPullTimestamp();
        } else if (_timestamp == 0) {
            _timestamp = block.timestamp;
        }

        for (uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 tokenId = _tokenIds[i];

            (address currentDelegatee, uint32 ts) = getDelegate(tokenId, _timestamp);

            if (currentDelegatee == address(0)) {
                revert TokenNotDelegated(tokenId);
            }

            _updateBalance(
                currentDelegatee,
                getVP(tokenId, ts), // oldVP
                getVP(tokenId, _timestamp), // newVP
                _timestamp
            );
        }
    }

    // Called by the escrow when the transfer of the token occurs..
    function moveDelegateVotes(address /* _from */, address /* _to */, uint256 _tokenId) public {
        if (_msgSender() != escrow) {
            revert OnlyEscrow();
        }

        (address currentDelegatee, uint256 ts) = getDelegate(_tokenId, block.timestamp);

        // delegatee is not set, so skip.
        if (currentDelegatee == address(0)) {
            return;
        }

        // When the token transfer occurs, we must clear out delegatee data
        // and not automatically re-delegate it as this must only be decided by
        // the receiver by calling `delegate`.

        _updateLatestBalance(currentDelegatee, getVP(_tokenId, ts), 0);
        _updateLatestDelegate(_tokenId, address(0));
    }

    /*//////////////////////////////////////////////////////////////
                        IVotes Function
    //////////////////////////////////////////////////////////////*/
    function getVotes(address _account) external view returns (uint256) {
        return getDelegationBalance(_account, block.timestamp);
    }

    function getPastVotes(address _account, uint256 _timepoint) external view returns (uint256) {
        return getDelegationBalance(_account, _timepoint);
    }

    function getPastTotalSupply(uint256 _timepoint) external view returns (uint256) {
        return IVotingEscrow(escrow).totalVotingPowerAt(_timepoint);
    }

    /*//////////////////////////////////////////////////////////////
                       Delegation Related Functions
    //////////////////////////////////////////////////////////////*/
    function getDelegationBalance(
        address _delegatee,
        uint256 _timestamp
    ) public view returns (uint256) {
        // Get the latest season's start before `_t`
        (uint48 seasonStart, ) = IClockSeason(clock).seasonTsAt(uint48(_timestamp));

        BalanceCheckpoint[] storage cps = balanceCheckpoints[_delegatee];

        uint256 pos = _upperBinaryLookup(cps, uint32(_timestamp));

        if (pos == 0) return 0;

        BalanceCheckpoint storage cp = cps[pos - 1];

        if (seasonStart > cp.timestamp) return 0;

        return cp.balance;
    }

    function getVP(uint256 _tokenId, uint256 _timestamp) public view returns (uint256) {
        return IVotingEscrow(escrow).votingPowerAt(_tokenId, _timestamp);
    }

    function getDelegate(
        uint256 _tokenId,
        uint256 _timestamp
    ) public view returns (address, uint32) {
        DelegateCheckpoint[] storage cps = delegationCheckpoints[_tokenId];

        if (cps.length == 0) {
            return (address(0), 0);
        }

        DelegateCheckpoint memory cp;

        if (_timestamp == block.timestamp) {
            cp = cps[cps.length - 1];
        } else {
            uint256 pos = _upperBinaryLookup(cps, _timestamp);
            if (pos != 0) {
                cp = cps[pos - 1];
            }
        }

        return (cp.delegatee, cp.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                        PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _updateLatestDelegate(uint256 _tokenId, address _delegatee) private {
        _updateDelegate(_tokenId, _delegatee, block.timestamp);
    }

    function _updateDelegate(uint256 _tokenId, address _delegatee, uint256 _when) private {
        delegationCheckpoints[_tokenId].push(DelegateCheckpoint(_delegatee, uint32(_when)));
    }

    function _updateLatestBalance(
        address _delegatee,
        uint256 _subtractAmount,
        uint256 _addAmount
    ) private {
        _updateBalance(_delegatee, _subtractAmount, _addAmount, block.timestamp);
    }

    /// @dev Note that if this function is called in the same tx multiple times,
    ///      it only uses single slot and extra gas comes only from writing to "dirty slot".
    function _updateBalance(
        address _delegatee,
        uint256 _subtractAmount,
        uint256 _addAmount,
        uint256 _when
    ) private {
        BalanceCheckpoint[] storage cps = balanceCheckpoints[_delegatee];
        uint256 length = cps.length;

        if (length == 0) {
            cps.push(BalanceCheckpoint(_addAmount.toUint224(), uint32(_when)));

            return;
        }

        uint256 pos = _upperBinaryLookup(cps, _when);
        
        BalanceCheckpoint storage lastCp = cps[length - 1];
        
        // if `pos` is equal to the length of array or more, that means
        // no element was found with greater timestamp than our `_when`.
        // In this case, it's a normal push operation only without
        // the need to shift elements.
        if (pos < length) {
            // Shift an array to the right
            for (uint256 i = length - 1; i > pos; i--) {
                cps[i] = cps[i - 1];
            }

            // [15, 24, 24]

            // move the last element to the new end.
            cps.push(lastCp);

            uint256 newBalance;

            // If pos is 0, there's no previous element, so use only `addAmount`.
            if (pos == 0) {
                newBalance = _addAmount;
            } else {
                newBalance = uint256(cps[pos - 1].balance) - _subtractAmount + _addAmount;
            }

            // store the new checkpoint at the pos.
            cps[pos] = BalanceCheckpoint(newBalance.toUint224(), uint32(_when));
        } else {
            uint224 balance = (uint256(lastCp.balance) - _subtractAmount + _addAmount).toUint224();
            if (lastCp.timestamp == block.timestamp) {
                lastCp.balance = balance;
            } else {
                cps.push(BalanceCheckpoint(balance, uint32(_when)));
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                        BINARY SEARCH HELPERS
    //////////////////////////////////////////////////////////////*/
    function _upperBinaryLookup(
        BalanceCheckpoint[] storage _checkpoints,
        uint256 _timestamp
    ) private view returns (uint256) {
        uint256 low = 0;
        uint256 high = _checkpoints.length;

        while (low < high) {
            uint256 mid = MathUpgradeable.average(low, high);
            if (_checkpoints[mid].timestamp > _timestamp) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }

        return high;
    }

    function _upperBinaryLookup(
        DelegateCheckpoint[] storage _checkpoints,
        uint256 _timestamp
    ) private view returns (uint256) {
        uint256 low = 0;
        uint256 high = _checkpoints.length;

        while (low < high) {
            uint256 mid = MathUpgradeable.average(low, high);
            if (_checkpoints[mid].timestamp > _timestamp) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }

        return high;
    }
}
