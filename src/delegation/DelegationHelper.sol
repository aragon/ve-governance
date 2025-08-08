/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {
    IVotesUpgradeable
} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {
    SafeCastUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {
    ReentrancyGuardUpgradeable as ReentrancyGuard
} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {
    PausableUpgradeable as Pausable
} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {IERC721EnumerableMintableBurnable as IERC721EMB} from "@lock/IERC721EMB.sol";

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {
    DaoAuthorizableUpgradeable as DaoAuthorizable
} from "@aragon/osx/core/plugin/dao-authorizable/DaoAuthorizableUpgradeable.sol";
import {console2 as console} from "forge-std/console2.sol";

import {
    IVotingEscrowIncreasingV1_2_0 as IVotingEscrow
} from "@escrow/IVotingEscrowIncreasing_v1_2_0.sol";
import {VotingEscrowV1_2_0 as VotingEscrow} from "@escrow/VotingEscrowIncreasing_v1_2_0.sol";

import {IClockV1_2_0 as IClock} from "@clock/IClock_v1_2_0.sol";

import {IEscrowIVotesAdapter, IDelegateMoveVoteRecipient} from "./IEscrowIVotesAdapter.sol";
import {CurveConstantLib} from "@libs/CurveConstantLib.sol";
import {SignedFixedPointMath} from "@libs/SignedFixedPointMathLib.sol";
import {IEscrowIVotesAdapter} from "./IEscrowIVotesAdapter.sol";

abstract contract DelegationHelper is IEscrowIVotesAdapter, Pausable, UUPSUpgradeable {
    /// @notice Address of the voting escrow contract that will track voting power
    address public escrow;

    /// @notice the mapping that stores how many token an address has delegated currently.
    mapping(address => uint256) public numberOfDelegatedTokens;

    /// @notice Efficiently stores which token is delegated.
    mapping(uint256 => uint256) private delegatedBitmap;

    error IncorrectTokenIds();

    modifier onlyEscrow() {
        if (_msgSender() != escrow) {
            revert OnlyEscrow();
        }

        _;
    }

    /// @notice The initializer.
    function __DelegationHelper_init(address _escrow) internal onlyInitializing {
        escrow = _escrow;
    }

    /// @inheritdoc IDelegateMoveVoteRecipient
    function splitDelegateVotes(
        TokenLock calldata _from,
        TokenLock calldata _to
    ) public virtual whenNotPaused onlyEscrow {
        if (_from.tokenId == 0 || _to.tokenId == 0) {
            revert IncorrectTokenIds();
        }

        bool isFromTokenDelegated = tokenIsDelegated(_from.tokenId);
        bool isToTokenDelegated = tokenIsDelegated(_to.tokenId);

        // If `x` is split into `x` and `y`, and `x` is delegated,
        // then automatically delegate `y` as well. This is to ensure that
        // later on, delegating `y` manually will revert, otherwise it would
        // cause votes to be double spent as original `x` that was delegated
        // already included the amount of `y`.
        if (isFromTokenDelegated) {
            numberOfDelegatedTokens[_from.account]++;
            _setDelegated(_to.tokenId, true);
            emit TokensDelegated(_to.account, delegates(_to.account), _getTokenIdList(_to.tokenId));
        }

        // TODO: if `x` not delegated, do we want to automatically delegate both `x` and `y` as long as delegate is set ?
    }

    /// @inheritdoc IDelegateMoveVoteRecipient
    function mergeDelegateVotes(
        TokenLock calldata _from,
        TokenLock calldata _to
    ) public virtual whenNotPaused onlyEscrow {
        if (_from.tokenId == 0 || _to.tokenId == 0) {
            revert IncorrectTokenIds();
        }

        bool isFromTokenDelegated = tokenIsDelegated(_from.tokenId);
        bool isToTokenDelegated = tokenIsDelegated(_to.tokenId);

        address fromDelegatee = delegates(_from.account);

        if (!isFromTokenDelegated) {
            // from is not delegated and to is delegated.
            if (isToTokenDelegated) {
                (int256 bias, int256 slope) = _getBiasAndSlope(
                    fromDelegatee,
                    _from.locked,
                    _positive
                );
                _checkpoint(bias, slope, fromDelegatee);
            }

            // If none of them are delegated, do nothing.
        } else {
            // from is delegated and to is delegated.
            // since both are already delegated, their amounts are already included in checkpoints.
            // We only need to mark `from` as false and decrease count since `from` actually
            // gets burnt(note that its amount moves in `to`)
            if (isToTokenDelegated) {
                numberOfDelegatedTokens[_from.account]--;
            } else {
                // from is delegated, but `to` is not delegated.
                // We must add `to`'s amount in the checkpoints. Otherwise, after the merge,
                // user can manually delegate `to` which's vp at the time will include
                // the total amount after the merge. This will cause double spend.
                // lock needs to be `to`'s amount.
                (int256 bias, int256 slope) = _getBiasAndSlope(
                    fromDelegatee,
                    _to.locked,
                    _positive
                );
                _checkpoint(bias, slope, fromDelegatee);

                _setDelegated(_to.tokenId, true);
                emit TokensDelegated(
                    _to.account,
                    delegates(_to.account),
                    _getTokenIdList(_to.tokenId)
                );
            }

            _setDelegated(_from.tokenId, false);
            emit TokensUndelegated(_from.account, fromDelegatee, _getTokenIdList(_from.tokenId));
        }
    }

    /// @inheritdoc IDelegateMoveVoteRecipient
    /// @dev This is called on `transfer`, `withdraw` and `createLock`.
    /// @notice Assumes that: if this is called on transfer, then it can only be called if _from and _to are different.
    function moveDelegateVotes(
        address _from,
        address _to,
        uint256 _tokenId,
        IVotingEscrow.LockedBalance memory _locked
    ) public virtual whenNotPaused onlyEscrow {
        address fromDelegatee = delegates(_from);
        address toDelegatee = delegates(_to);

        // undelegated src and recipient, no balances to update
        if (fromDelegatee == address(0) && toDelegatee == address(0)) {
            return;
        }

        uint256[] memory tokenIds = _getTokenIdList(_tokenId);

        if (fromDelegatee != address(0)) {
            if (tokenIsDelegated(_tokenId)) {
                (int256 bias, int256 slope) = _getBiasAndSlope(fromDelegatee, _locked, _negative);
                _checkpoint(bias, slope, fromDelegatee);

                numberOfDelegatedTokens[_from]--;
                emit TokensUndelegated(_from, fromDelegatee, tokenIds);
            }
        }

        // Giorgi has tokenId = 5 and his delegatee is bob.
        // Giorgi transfers tokenId = 5 to Alice.

        // 1. alice doesn't have a delegatee.
        // Shouldn't emit TokensDelegated event
        // 2. alice has a delegatee
        // Should emit TokensDelegated event
        // 3.
        if (toDelegatee != address(0)) {
            (int256 bias, int256 slope) = _getBiasAndSlope(toDelegatee, _locked, _positive);
            _checkpoint(bias, slope, toDelegatee);

            numberOfDelegatedTokens[_to]++;
            _setDelegated(_tokenId, true);
            emit TokensDelegated(_to, toDelegatee, tokenIds);
        } else {
            // else this is new delegate voting power being burned
            _setDelegated(_tokenId, false);
        }

        if (fromDelegatee != toDelegatee) {
            IVotingEscrow(escrow).updateVotingPower(fromDelegatee, toDelegatee);
        }
    }

    /// @dev Whether token is currently delegated or not.
    function tokenIsDelegated(uint256 tokenId) public view virtual returns (bool) {
        uint256 bucket = tokenId >> 8;
        uint256 mask = 1 << (tokenId & 0xff);
        return (delegatedBitmap[bucket] & mask) != 0;
    }

    /// @dev Internal helper function to set token delegated to true by using bitmap operations.
    function _setDelegated(uint256 tokenId, bool value) internal virtual {
        uint256 bucket = tokenId >> 8; // tokenId / 256
        uint256 mask = 1 << (tokenId & 0xff); // tokenId % 256

        if (value) {
            delegatedBitmap[bucket] |= mask;
        } else {
            delegatedBitmap[bucket] &= ~mask;
        }
    }

    function _positive(int256 _value) internal pure returns (int256) {
        return _value;
    }

    function _negative(int256 _value) internal pure returns (int256) {
        return -_value;
    }

    function _getTokenIdList(uint256 _tokenId) private pure returns (uint256[] memory tokenIds) {
        tokenIds = new uint256[](1);
        tokenIds[0] = _tokenId;
    }

    /*//////////////////////////////////////////////////////////////
                        Abstract Functions.
    //////////////////////////////////////////////////////////////*/

    function delegates(address _account) public view virtual returns (address);

    function _getBiasAndSlope(
        address _delegatee,
        IVotingEscrow.LockedBalance memory _locked,
        function(int256) view returns (int256) op
    ) internal virtual returns (int256, int256);

    function _checkpoint(
        int256 _totalBias,
        int256 _totalSlope,
        address _delegatee
    ) internal virtual;

    function _checkpoint(
        int256 _totalBias,
        int256 _totalSlope,
        address _delegatee,
        uint256 _transitionCount
    ) internal virtual;
}
