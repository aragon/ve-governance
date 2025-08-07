pragma solidity ^0.8.17;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {EscrowBase} from "../../base/EscrowBase.sol";

import {console2 as console} from "forge-std/console2.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig, MultisigSetup} from "@aragon/multisig/MultisigSetup.sol";
import {MockERC20} from "@mocks/MockERC20.sol";
import {ILockedBalanceIncreasing} from "@escrow/IVotingEscrowIncreasing.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";
import {Test} from "forge-std/Test.sol";

import {
    Lock,
    Clock,
    VotingEscrow,
    ExitQueue,
    SimpleGaugeVoter,
    SimpleGaugeVoterSetup,
    IEscrowCurveIncreasing,
    IEscrowCurveTokenStorage,
    EscrowIVotesAdapter,
    VotingEscrow,
    Curve
} from "../../versions.sol";
import {IERC721EnumerableMintableBurnable as IERC721EMB} from "@lock/IERC721EMB.sol";

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {CommonBase} from "forge-std/Base.sol";

contract DelegationHandler is StdUtils, StdCheats, CommonBase {
    using EnumerableSet for EnumerableSet.UintSet;

    IERC721EMB private lockNft;
    VotingEscrow private escrow;
    EscrowIVotesAdapter private ivotesAdapter;
    Curve private curve;
    ExitQueue private queue;

    MockERC20 private token;
    uint256 private maxTime;
    uint256 private checkpointInterval;

    // Ghost variables
    address[] public actors;

    // This gives a list of tokens that user owns.
    mapping(address => EnumerableSet.UintSet) internal ownedTokens;

    // This gives us a list of addresses that have tokens.

    // Outgoing tokens give a set that user has delegated to others.
    mapping(address => EnumerableSet.UintSet) internal outgoingTokens;

    // incoming tokens give a set of what tokens are delegated to the user.
    mapping(address => EnumerableSet.UintSet) internal incomingTokens;

    // Active tokenIds..
    EnumerableSet.UintSet internal activeTokenIds;

    uint256 public totalLocked;

    constructor(
        address _escrow,
        address _curve,
        address _lockNft,
        address _ivotesAdapter,
        address _queue,
        uint256 _maxTime,
        uint256 _checkpointInterval
    ) {
        escrow = VotingEscrow(_escrow);
        curve = Curve(_curve);
        lockNft = IERC721EMB(_lockNft);
        token = MockERC20(escrow.token());
        ivotesAdapter = EscrowIVotesAdapter(_ivotesAdapter);
        queue = ExitQueue(_queue);

        maxTime = _maxTime;
        checkpointInterval = _checkpointInterval;

        // create 5 actors.
        for (uint256 i = 10; i <= 15; i++) {
            actors.push(address(uint160(i)));
        }
    }

    function setDelegateAddress(uint256 _delegatorIdx, uint256 _delegateeIdx) public {
        address delegator = _getSender(_delegatorIdx);
        address delegatee = _getSender(_delegateeIdx);

        if (ivotesAdapter.numberOfDelegatedTokens(delegator) != 0) {
            return;
        }

        vm.prank(delegator);
        ivotesAdapter.setDelegateAddress(delegatee);
    }

    function delegate(
        uint256 _jumpSeed,
        uint256 _seedAddr,
        uint256 _numToDelegateSeed
    ) public adjustTimestamp(_jumpSeed) {
        address msgSender = _getSender(_seedAddr);
        address delegatee = ivotesAdapter.delegates(msgSender);

        // TODO: it might be a good option to ensure that the return here doesn't occur - i.e 
        // when delegate is called in a sequence, it always is called
        // with someone that already has a delegatee and has tokens undelegated that he can delegate.
        // This way, delegate calls will not be wasted by those that don't have delegatee set or tokens = 0.
        // To do this, ` address msgSender = _getSender(_seedAddr);` is incorrect, we probably need
        // to track the users in separate structure which holds only those that have delegates set and tokens !=0.
        // then _seedAddr will get it from that list/structure.

        // TODO 3: Echidna....
        if (ownedTokens[msgSender].length() == 0 || delegatee == address(0)) {
            return;
        }

        // If all tokens are delegated, return early to avoid reverts for fuzzing.
        // the list will be non-delegated tokens.
        // seed decides whether to use all or only some of them
        uint256[] memory tokens = getTokenIdsBasedOnSeed(
            getNonDelegatedTokens(msgSender),
            _numToDelegateSeed
        );

        if (tokens.length == 0) return;

        _transitionIfTooOld(delegatee);
        vm.prank(msgSender);
        ivotesAdapter.delegate(tokens);

        for (uint256 i = 0; i < tokens.length; i++) {
            incomingTokens[delegatee].add(tokens[i]);
            outgoingTokens[msgSender].add(tokens[i]);
        }
    }

    function undelegate(
        uint256 _jumpSeed,
        uint256 _seedAddr,
        uint256 _numToUndelegateSeed
    ) public adjustTimestamp(_jumpSeed) {
        address msgSender = _getSender(_seedAddr);
        address delegatee = ivotesAdapter.delegates(msgSender);

        if (ownedTokens[msgSender].length() == 0 || delegatee == address(0)) {
            return;
        }

        // the list will be delegated tokens.
        // seed decides whether to use all or only some of them
        uint256[] memory tokens = getTokenIdsBasedOnSeed(
            getOutgoingTokens(msgSender),
            _numToUndelegateSeed
        );

        if (tokens.length == 0) return;

        _transitionIfTooOld(delegatee);

        vm.prank(msgSender);
        ivotesAdapter.undelegate(tokens);

        for (uint256 i = 0; i < tokens.length; i++) {
            incomingTokens[delegatee].remove(tokens[i]);
            outgoingTokens[msgSender].remove(tokens[i]);
        }
    }

    function createLock(
        uint256 _jumpSeed,
        uint256 _value,
        uint256 _seedAddr
    ) external adjustTimestamp(_jumpSeed) returns (uint256) {
        _value = _bound(_value, escrow.minDeposit(), type(uint96).max);
        address msgSender = _getSender(_seedAddr);
        address delegatee = ivotesAdapter.delegates(msgSender);

        _transitionIfTooOld(delegatee);

        // mint tokens to sender and approve to escrow
        // so escrow can transfer it from sender.
        token.mint(msgSender, _value);
        vm.startPrank(msgSender);
        token.approve(address(escrow), _value);
        uint256 tokenId = escrow.createLock(_value);
        vm.stopPrank();

        // Ghost state variables
        totalLocked += _value;
        activeTokenIds.add(tokenId);
        ownedTokens[msgSender].add(tokenId);

        // If sender has a delegatee already set,
        // tokenId automatically gets delegated.
        if (delegatee != address(0)) {
            incomingTokens[delegatee].add(tokenId);
            outgoingTokens[msgSender].add(tokenId);
        }

        return tokenId;
    }

    function merge(
        uint256 _jumpSeed,
        uint256 _from,
        uint256 _to,
        uint256 _seedAddr
    ) external adjustTimestamp(_jumpSeed) {
        address msgSender = _getSender(_seedAddr);
        address delegatee = ivotesAdapter.delegates(msgSender);

        // If the user doesn't own at least 2 tokens,
        // return early as there's nothing to merge.
        uint256 len = ownedTokens[msgSender].length();
        if (len < 2) return;

        _from = _bound(_from, 0, len - 1);
        _to = _bound(_to, 0, len - 1);
        _to = _from == _to ? (_to + 1) % len : _to;

        uint256 fromId = ownedTokens[msgSender].at(_from);
        uint256 toId = ownedTokens[msgSender].at(_to);

        {
            ILockedBalanceIncreasing.LockedBalance memory fromLocked = escrow.locked(fromId);
            ILockedBalanceIncreasing.LockedBalance memory toLocked = escrow.locked(toId);

            // Starts not equal and one of the token is not mature or both.
            if (!escrow.canMerge(fromLocked, toLocked)) {
                uint256 fromEnd = fromLocked.start + maxTime;
                uint256 toEnd = toLocked.start + maxTime;

                // If tokens have different start dates, we can only merge if
                // they are both mature. So move to time so they are both mature.
                if (fromEnd >= block.timestamp || toEnd >= block.timestamp) {
                    uint256 biggerTs = fromEnd > toEnd ? fromEnd : toEnd;
                    vm.warp(biggerTs + 1);
                }
            }

            _transitionIfTooOld(delegatee);
        }

        bool isFromTokenDelegated = ivotesAdapter.tokenIsDelegated(fromId);

        vm.prank(msgSender);
        escrow.merge(fromId, toId);

        // Ghost state variables
        ownedTokens[msgSender].remove(fromId);
        activeTokenIds.remove(fromId);

        if (delegatee != address(0)) {
            // If `from` token was delegated and is merged
            // into `to`, `to` automatically becomes delegated.
            if (isFromTokenDelegated) {
                incomingTokens[delegatee].add(toId);
                outgoingTokens[msgSender].add(toId);
            }

            incomingTokens[delegatee].remove(fromId);
            outgoingTokens[msgSender].remove(fromId);
        }
    }

    function split(
        uint256 _jumpSeed,
        uint256 _from,
        uint256 _value,
        uint256 _seedAddr
    ) public adjustTimestamp(_jumpSeed) {
        address msgSender = _getSender(_seedAddr);
        address delegatee = ivotesAdapter.delegates(msgSender);

        _transitionIfTooOld(delegatee);

        if (ownedTokens[msgSender].length() == 0) return;

        _from = _bound(_from, 0, ownedTokens[msgSender].length() - 1);

        uint256 fromId = ownedTokens[msgSender].at(_from);

        uint256 currentAmount = escrow.locked(fromId).amount;
        uint256 minDeposit = escrow.minDeposit();

        // Ensure that after split, both tokens have more than `minDeposit`.
        if (currentAmount < 2 * minDeposit) return;

        _value = _bound(_value, minDeposit, currentAmount - minDeposit);

        bool isFromTokenDelegated = ivotesAdapter.tokenIsDelegated(fromId);

        vm.prank(msgSender);
        uint256 newTokenId = escrow.split(fromId, _value);

        // Ghost state variables
        ownedTokens[msgSender].add(newTokenId);
        activeTokenIds.add(newTokenId);

        // When `from` is split, new token id is minted. We only
        // delegate it automatically if `from` was also delegated.
        if (delegatee != address(0) && isFromTokenDelegated) {
            incomingTokens[delegatee].add(fromId);
            outgoingTokens[msgSender].add(fromId);

            incomingTokens[delegatee].add(newTokenId);
            outgoingTokens[msgSender].add(newTokenId);
        }
    }

    function withdraw(uint256 _jumpSeed, uint256 _tokenIdSeed) public adjustTimestamp(_jumpSeed) {
        if (activeTokenIds.length() == 0) return;

        _tokenIdSeed = _bound(_tokenIdSeed, 0, activeTokenIds.length() - 1);

        uint256 tokenId = activeTokenIds.at(_tokenIdSeed);
        address owner = lockNft.ownerOf(tokenId);

        if (block.timestamp == curve.tokenPointHistory(tokenId, 1).writtenTs) {
            vm.warp(block.timestamp + 1);
        }

        address delegatee = ivotesAdapter.delegates(owner);
        uint256 amount = escrow.locked(tokenId).amount;

        _transitionIfTooOld(delegatee);
        vm.startPrank(owner);
        lockNft.approve(address(escrow), tokenId);
        escrow.beginWithdrawal(tokenId);

        vm.warp(queue.queue(tokenId).exitDate + 1);
        escrow.withdraw(tokenId);
        vm.stopPrank();

        // Ghost state variables
        totalLocked -= amount;
        activeTokenIds.remove(tokenId);
        ownedTokens[owner].remove(tokenId);

        if (delegatee != address(0)) {
            incomingTokens[delegatee].remove(tokenId);
            outgoingTokens[owner].remove(tokenId);
        }
    }

    // ======================== Helper Functions ===================

    // The list of addresses that participate in testing.
    function getActors() public view returns (address[] memory) {
        return actors;
    }

    // The list of token ids that `_account` has not delegated yet.
    function getNonDelegatedTokens(address _account) public view returns (uint256[] memory) {
        uint256[] memory tokens = _fromSetToArray(ownedTokens[_account]);
        uint256[] memory temp = new uint256[](tokens.length);
        uint256 count = 0;

        // Only delegate those tokens that are not
        // yet delegated to avoid reverts.
        for (uint256 i = 0; i < tokens.length; ++i) {
            if (!ivotesAdapter.tokenIsDelegated(tokens[i])) {
                temp[count++] = tokens[i];
            }
        }

        assembly {
            mstore(temp, count)
        }

        return temp;
    }

    // To ensure more randomization, this function helps `delegate/undelegate`
    // functions to decide how many tokens to undelegate/delegate. Alternative
    // is to always delegate/undelegate `_tokenIds`, but this would be more
    // predeterministic and not fully randomized.
    function getTokenIdsBasedOnSeed(
        uint256[] memory _tokenIds,
        uint256 _seed
    ) public view returns (uint256[] memory) {
        if (_tokenIds.length == 0) return new uint256[](0);

        uint256 numToDelegate = _bound(_seed, 1, _tokenIds.length);
        uint256[] memory newTokens = new uint256[](numToDelegate);
        for (uint256 i = 0; i < numToDelegate; i++) {
            newTokens[i] = _tokenIds[i];
        }

        return newTokens;
    }

    // The list of token ids that `_account` has been delegated with.
    function getIncomingTokens(address _account) public view returns (uint256[] memory) {
        return _fromSetToArray(incomingTokens[_account]);
    }

    // The list of token ids that `_account` has delegated.
    function getOutgoingTokens(address _account) public view returns (uint256[] memory) {
        return _fromSetToArray(outgoingTokens[_account]);
    }

    // The list of token ids that haven't been destroyed(with merge or withdraw)
    function getActiveTokenIds() public view returns (uint256[] memory) {
        return _fromSetToArray(activeTokenIds);
    }

    // Helper function to convert set into an array.
    function _fromSetToArray(
        EnumerableSet.UintSet storage _set
    ) private view returns (uint256[] memory) {
        uint256 length = _set.length();
        uint256[] memory ids = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            ids[i] = _set.at(i);
        }

        return ids;
    }

    // Adjust timestamps so that each function call
    // doesn't get called in the same block.timestamp.
    modifier adjustTimestamp(uint256 timeJumpSeed) {
        uint256 timeJump = _bound(timeJumpSeed, 0, 40 days);
        uint256 warpTo = block.timestamp + timeJump;

        // We don't allow createLock/merge/split
        // at the week intervals. so if time
        if (warpTo % checkpointInterval == 0) {
            warpTo++;
        }
        vm.warp(warpTo);
        _;
    }

    function _getSender(uint256 _seedAddr) private view returns (address) {
        return actors[_bound(_seedAddr, 0, actors.length - 1)];
    }

    // The checkpoint functions in the Escrow and EscrowIVotesAdapter are designed such that
    // When a new token is created/merged/split/withdrawal/delegate/undelegated, it first
    // finds the last global point and starts looping from it on week duration(possibly till current time)
    // to update bias on each week. Such design ensures that total supply can be calculated on chain
    // and not result in out of gas error. In the loops, we use `255` which is the maximum
    // number of weeks it can fill in before the last point and the new point. Note that
    // If last point was created for more than 254.00..1 weeks ago, this can result
    // in wrong calculation of total supplies. This is because at the 255th iteration,
    // the week it will end up will still be in the past. Assuming this week ts is denoted with `X`,
    // This week is where we would also add new point's bias and slope. When total supply is called,
    // last point stored will be grabbed as `X` and it would start looping from this to current time
    // to sum up remaining parts for total supply generation, but note that at `X`, we already stored
    // new point's bias, so total supply will include this bias/slope second time, causing
    // the wrong calculation. This problem is avoided by 2 important realizations:
    // In EscrowIVotesAdapter, it must be ensured that when a new operation occurs, each delegate's last point
    // is stored no more than 254.1 weeks ago. If this is not the case, then manual transition function
    // must be called to fill in each week. In this case, no wrong calculation would occur, because
    // manual transition only fills in weeks between last and current time and doesn't add
    // non-zero bias/slope (which is the case when checkpoint is called with creat lock/merge/split/...).
    function _transitionIfTooOld(address _delegatee) private {
        uint256 latestPointIndex = ivotesAdapter.latestPointIndex(_delegatee);

        (, , uint256 writtenTs) = ivotesAdapter.pointHistory(_delegatee, latestPointIndex);
        uint256 lastPointCheckpointDiff = (block.timestamp - writtenTs) / checkpointInterval;
        if (lastPointCheckpointDiff >= 254) {
            ivotesAdapter.checkpointTransition(_delegatee, lastPointCheckpointDiff + 1);
        }
    }
}
