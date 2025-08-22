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
    SimpleGaugeVoter as GaugeVoter,
    IGaugeVote,
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
    using EnumerableSet for EnumerableSet.AddressSet;

    IERC721EMB private lockNft;
    VotingEscrow private escrow;
    EscrowIVotesAdapter private ivotesAdapter;
    Curve private curve;
    ExitQueue private queue;
    GaugeVoter private voter;

    MockERC20 private token;
    uint256 private maxTime;
    uint256 private checkpointInterval;

    // ======= Ghost variables =========

    // The addresses that participate in testing
    address[] public actors;

    // The gauge addresses for which users can vote on AddressGaugeVoter
    address[] public gauges;

    // The list of tokens that user owns.
    mapping(address => EnumerableSet.UintSet) internal ownedTokens;

    // The list of addresses that have vp > 0.
    EnumerableSet.AddressSet internal delegateesWithVpPower;

    // The set of tokens that user has delegated to his/her delegatee.
    mapping(address => EnumerableSet.UintSet) internal outgoingTokens;

    // The set of tokens thatare delegated to the user.
    mapping(address => EnumerableSet.UintSet) internal incomingTokens;

    // Active tokenIds - withdraw and merge cause removal of the token id.
    EnumerableSet.UintSet internal activeTokenIds;

    // Track how much ERC20 token value is stored inside the escrow.
    uint256 public totalLocked;

    /// All the contract addresses necessary for the handler to work.
    struct Contracts {
        address escrow;
        address curve;
        address lockNft;
        address ivotesAdapter;
        address queue;
        address voter;
    }

    // Number that is used to choose how many actors
    // and gauges we will test the invariants.
    uint256 private constant COUNT = 5;

    constructor(
        Contracts memory _c,
        address _admin,
        uint256 _maxTime,
        uint256 _checkpointInterval
    ) {
        escrow = VotingEscrow(_c.escrow);
        curve = Curve(_c.curve);
        lockNft = IERC721EMB(_c.lockNft);
        token = MockERC20(escrow.token());
        ivotesAdapter = EscrowIVotesAdapter(_c.ivotesAdapter);
        voter = GaugeVoter(_c.voter);
        queue = ExitQueue(_c.queue);

        maxTime = _maxTime;
        checkpointInterval = _checkpointInterval;

        // create 5 actors.
        for (uint256 i = 10; i < 10 + COUNT; i++) {
            actors.push(address(uint160(i)));
        }

        // create 5 gauges
        for (uint256 i = 20; i < 20 + COUNT; i++) {
            address gauge = address(uint160(i));

            vm.prank(_admin);
            voter.createGauge(gauge, "metadata");

            gauges.push(gauge);
        }

        vm.prank(_admin);
        voter.setEnableUpdateVotingPowerHook(true);
    }

    function vote(
        uint256 _seedAddr,
        uint8[COUNT] memory _gaugeSeeds,
        uint64[COUNT] memory _weights
    ) public {
        address[] memory _delegateesWithPower = getDelegateesWithPower();
        // @jordan: this will presumably, and silently, cause a lot of invariants to pass
        // if we don't also check that we have delegatees w. voting power
        if (_delegateesWithPower.length == 0) return;

        _seedAddr = _bound(_seedAddr, 0, _delegateesWithPower.length - 1);
        address sender = _delegateesWithPower[_seedAddr];

        // @jordan what's the signifcance of 6 when COUNT is 5
        bool[COUNT] memory used;
        uint256 count = 0;

        IGaugeVote.GaugeVote[] memory votes = new IGaugeVote.GaugeVote[](_gaugeSeeds.length);
        for (uint256 i = 0; i < _gaugeSeeds.length; i++) {
            // @jordan grab a random gauge index based on the seed
            uint256 index = uint256(_gaugeSeeds[i]) % gauges.length;
            _weights[i] = uint64(_bound(_weights[i], 1, type(uint64).max));

            address gauge = gauges[index];
            // Ensure that votes don't contain duplicate gauges
            // to avoid reverts in the EscrowIVotesAdapter.
            // @jordan so this basically guarantees >= 1 unique vote, very nice
            if (!used[index]) {
                used[index] = true;
                votes[count++] = IGaugeVote.GaugeVote(_weights[i], gauge);
            }
        }

        assembly {
            mstore(votes, count)
        }

        if (!voter.votingActive()) {
            vm.warp(voter.epochVoteStart() + 1);
        }

        vm.prank(sender);
        voter.vote(votes);
    }

    function setDelegateAddress(uint256 _delegatorIdx, uint256 _delegateeIdx) public {
        address delegator = _getAddress(_delegatorIdx);
        address delegatee = _getAddress(_delegateeIdx);

        if (ivotesAdapter.numberOfDelegatedTokens(delegator) != 0) {
            return;
        }

        vm.prank(delegator);
        ivotesAdapter.setDelegateAddress(delegatee);
    }

    function delegate(
        uint256 _jumpSeed,
        uint256 _senderSeed,
        uint256 _delegateeSeed
    ) public adjustTimestamp(_jumpSeed) {
        address msgSender = _getAddress(_senderSeed);
        address newDelegatee = _getAddress(_delegateeSeed);
        address currentDelegatee = ivotesAdapter.delegates(msgSender);

        // @jordan maybe this function should be added somewhere in the src
        _transitionIfTooOld(newDelegatee);
        _transitionIfTooOld(currentDelegatee);

        vm.prank(msgSender);
        ivotesAdapter.delegate(newDelegatee);

        uint256[] memory tokens = _fromSetToArray(ownedTokens[msgSender]);

        // Ghost state variables
        for (uint256 i = 0; i < tokens.length; i++) {
            incomingTokens[newDelegatee].add(tokens[i]);
            if (newDelegatee != currentDelegatee) {
                incomingTokens[currentDelegatee].remove(tokens[i]);
            }

            // @jordan do we clear previous outgoing tokens?
            // I guess this being enumerable set it just checks for existence and
            // adds if needed
            outgoingTokens[msgSender].add(tokens[i]);
        }

        if (ivotesAdapter.getVotes(newDelegatee) != 0) {
            delegateesWithVpPower.add(newDelegatee);
        }

        if (ivotesAdapter.getVotes(currentDelegatee) == 0) {
            delegateesWithVpPower.remove(currentDelegatee);
        }
    }

    function delegateSpecificTokens(
        uint256 _jumpSeed,
        uint256 _senderSeed,
        uint256 _numToDelegateSeed
    ) public adjustTimestamp(_jumpSeed) {
        address msgSender = _getAddress(_senderSeed);
        address delegatee = ivotesAdapter.delegates(msgSender);

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

        // Ghost state variables
        for (uint256 i = 0; i < tokens.length; i++) {
            incomingTokens[delegatee].add(tokens[i]);
            outgoingTokens[msgSender].add(tokens[i]);
        }

        if (ivotesAdapter.getVotes(delegatee) != 0) {
            delegateesWithVpPower.add(delegatee);
        }
    }

    function undelegate(
        uint256 _jumpSeed,
        uint256 _senderSeed,
        uint256 _numToUndelegateSeed
    ) public adjustTimestamp(_jumpSeed) {
        address msgSender = _getAddress(_senderSeed);
        address delegatee = ivotesAdapter.delegates(msgSender);

        // @jordan wonder if we need to check how many times we called state changes versus early returns
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

        // Ghost state variables
        for (uint256 i = 0; i < tokens.length; i++) {
            incomingTokens[delegatee].remove(tokens[i]);
            outgoingTokens[msgSender].remove(tokens[i]);
        }

        if (ivotesAdapter.getVotes(delegatee) == 0) {
            delegateesWithVpPower.remove(delegatee);
        }
    }

    function createLock(
        uint256 _jumpSeed,
        uint256 _value,
        uint256 _senderSeed
    ) external adjustTimestamp(_jumpSeed) returns (uint256 tokenId) {
        _value = _bound(_value, escrow.minDeposit(), type(uint96).max);
        address msgSender = _getAddress(_senderSeed);
        address delegatee = ivotesAdapter.delegates(msgSender);

        _transitionIfTooOld(delegatee);

        // mint tokens to sender and approve to escrow
        // so escrow can transfer it from sender.
        token.mint(msgSender, _value);
        vm.startPrank(msgSender);
        token.approve(address(escrow), _value);
        tokenId = escrow.createLock(_value);
        vm.stopPrank();

        // Ghost state variables
        totalLocked += _value;
        activeTokenIds.add(tokenId);
        ownedTokens[msgSender].add(tokenId);

        // If sender has a delegatee already set,
        // tokenId automatically gets delegated.
        if (delegatee != address(0)) {
            if (ivotesAdapter.getVotes(delegatee) != 0) {
                delegateesWithVpPower.add(delegatee);
            }
            incomingTokens[delegatee].add(tokenId);
            outgoingTokens[msgSender].add(tokenId);
        }

        return tokenId;
    }

    function merge(
        uint256 _jumpSeed,
        uint256 _from,
        uint256 _to,
        uint256 _senderSeed
    ) external adjustTimestamp(_jumpSeed) {
        address msgSender = _getAddress(_senderSeed);
        address delegatee = ivotesAdapter.delegates(msgSender);

        // If the user doesn't own at least 2 tokens,
        // return early as there's nothing to merge.
        uint256 len = ownedTokens[msgSender].length();
        if (len < 2) return;

        _from = _bound(_from, 0, len - 1);
        _to = _bound(_to, 0, len - 1);
        // @jordan looks good assume this can't resolve to _from due to +1 and modulo
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
            if (ivotesAdapter.getVotes(delegatee) != 0) {
                delegateesWithVpPower.add(delegatee);
            }
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
        uint256 _senderSeed
    ) public adjustTimestamp(_jumpSeed) {
        address msgSender = _getAddress(_senderSeed);
        address delegatee = ivotesAdapter.delegates(msgSender);
        // @jordan wonder if we need this in src again
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
            if (ivotesAdapter.getVotes(delegatee) > 0) {
                delegateesWithVpPower.add(delegatee);
            }
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

        // Withdraw is disallowed in the same block as createLock/merge/split,
        // so warp if last point was created in the same block.
        if (block.timestamp == curve.tokenPointHistory(tokenId, 1).writtenTs) {
            vm.warp(block.timestamp + 1);
        }

        address delegatee = ivotesAdapter.delegates(owner);
        uint256 amount = escrow.locked(tokenId).amount;

        _transitionIfTooOld(delegatee);
        vm.startPrank(owner);
        lockNft.approve(address(escrow), tokenId);
        escrow.beginWithdrawal(tokenId);

        // @jordan maybe we should wrap to separate function to allow beginWithdrawal, withdraw in separate functions
        vm.warp(queue.queue(tokenId).exitDate + 1);
        escrow.withdraw(tokenId);
        vm.stopPrank();

        // Ghost state variables
        totalLocked -= amount;
        activeTokenIds.remove(tokenId);
        ownedTokens[owner].remove(tokenId);

        if (delegatee != address(0)) {
            if (ivotesAdapter.getVotes(delegatee) == 0) {
                delegateesWithVpPower.remove(delegatee);
            }
            incomingTokens[delegatee].remove(tokenId);
            outgoingTokens[owner].remove(tokenId);
        }
    }

    function transfer(uint256 _jumpSeed, uint192 _fromSeed, uint192 _toSeed) public adjustTimestamp(_jumpSeed) {
        (address from, uint256 tokenId) = getUserWithToken(_fromSeed);
        if(from == address(0)) return;
    
        // Select `to` from remaining users (excluding `from`)
        address to;
        for (uint256 i = 0; i < COUNT; i++) {
            uint256 idx = (_toSeed + i) % 5;
            if (actors[idx] != from) {
                to = actors[idx];
                break;
            }
        }

        if(to == address(0)) return;

        // TODO: remove
        if(from == to) return;
        
        // vm.prank(from);
        // lockNft.transferFrom(from, to, tokenId);

        // ownedTokens[from].remove(tokenId);
        // ownedTokens[to].add(tokenId);

        // address fromDelegatee = ivotesAdapter.delegates(from);
        // address toDelegatee = ivotesAdapter.delegates(to);
        
        // if(fromDelegatee != address(0)) {
        //     outgoingTokens[from].remove(tokenId);
        //     incomingTokens[fromDelegatee].remove(tokenId);
        //     if (ivotesAdapter.getVotes(fromDelegatee) == 0) {
        //         delegateesWithVpPower.remove(fromDelegatee);
        //     }
        // }

        // if(toDelegatee != address(0)) {
        //     incomingTokens[toDelegatee].add(tokenId);
        //     outgoingTokens[to].add(tokenId);
        //     if (ivotesAdapter.getVotes(toDelegatee) != 0) {
        //         delegateesWithVpPower.add(toDelegatee);
        //     }
        // }
    }

    // @jordan should add a transfer function

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

        // @jordan: this is ghetto trimming by telling the array it's
        // len count instead of tokens.length.
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

    function getUserWithToken(uint192 _seed) public view returns(address, uint256) {
        // Try each user starting from seed index
        address selectedUser;
        uint256 tokenId;
        
        for (uint256 i = 0; i < COUNT; i++) {
            uint256 index = (_seed + i) % 5;
            address actor = actors[index];
            uint256[] memory actorTokens = _fromSetToArray(ownedTokens[actor]);
            if (actorTokens.length > 0) {
                selectedUser = actor;
                tokenId = actorTokens[_seed % actorTokens.length];
                break;
            }
        }
        
        return (selectedUser, tokenId); 
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

    // The list of addresses to which at least 1 token is delegated(i.e whose vp > 0)
    function getDelegateesWithPower() public view returns (address[] memory) {
        return _fromSetToArray(delegateesWithVpPower);
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

    // Helper function to convert set into an array.
    function _fromSetToArray(
        EnumerableSet.AddressSet storage _set
    ) private view returns (address[] memory) {
        uint256 length = _set.length();
        address[] memory addresses = new address[](length);

        for (uint256 i = 0; i < length; i++) {
            addresses[i] = _set.at(i);
        }

        return addresses;
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

    function _getAddress(uint256 _seedAddr) private view returns (address) {
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
