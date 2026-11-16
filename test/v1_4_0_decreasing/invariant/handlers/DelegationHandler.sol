pragma solidity ^0.8.17;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {console2 as console} from "forge-std/console2.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig, MultisigSetup} from "@aragon/multisig/src/MultisigSetup.sol";
import {MockERC20} from "@mocks/MockERC20.sol";
import {ILockedBalanceIncreasing} from "@escrow/IVotingEscrowDecreasing.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";
import {Test} from "forge-std/Test.sol";

import {
    Lock,
    Clock,
    VotingEscrow,
    SimpleGaugeVoter as GaugeVoter,
    IGaugeVote,
    SimpleGaugeVoterSetup,
    IEscrowCurveDecreasing,
    IEscrowCurveTokenStorage,
    EscrowIVotesAdapter,
    VotingEscrow,
    Curve
} from "../../versions.sol";
import {IERC721EnumerableMintableBurnable as IERC721EMB} from "@lock/IERC721EMB.sol";
import {RewardsDistributor, IRewardsDistributor} from "../../../../src/rewards/RewardsDistributor.sol";
import {RewardsClaimAggregator} from "../../../../src/rewards/RewardsClaimAggregator.sol";

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
    Clock private clock;
    Curve private curve;
    GaugeVoter private voter;
    RewardsClaimAggregator private rewardsAggregator;
    RewardsDistributor[3] private rewardsDistributors;
    MockERC20[3] private rewardsTokens;
    address rewardsSender;
    uint256[3] public triggeredRewards;

    MockERC20 private token;
    uint256 private maxTime;
    uint256 private checkpointInterval;

    enum Action {
        ADD,
        REMOVE,
        TRANSFER
    }

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

    // The set of tokens that are delegated to the user.
    mapping(address => EnumerableSet.UintSet) internal incomingTokens;

    // The set of tokens for which begin withdrawal started.
    EnumerableSet.UintSet internal withdrawTokens;

    // Active tokenIds - withdraw(not withdraw) and merge
    // cause removal of the token id.
    EnumerableSet.UintSet internal activeTokenIds;

    mapping(uint256 => bool) public isPermanentLock;

    // Track how much ERC20 token value is stored inside the escrow.
    uint256 public totalLocked;

    /// All the contract addresses necessary for the handler to work.
    struct Contracts {
        address escrow;
        address curve;
        address clock;
        address lockNft;
        address ivotesAdapter;
        address voter;
        address rewardsAggregator;
        RewardsDistributor[3] rewardsDistributors;
        MockERC20[3] rewardsTokens;
        address rewardsSender;
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
        clock = Clock(_c.clock);
        lockNft = IERC721EMB(_c.lockNft);
        token = MockERC20(escrow.token());
        ivotesAdapter = EscrowIVotesAdapter(_c.ivotesAdapter);
        voter = GaugeVoter(_c.voter);
        rewardsAggregator = RewardsClaimAggregator(_c.rewardsAggregator);
        rewardsDistributors = [
            RewardsDistributor(_c.rewardsDistributors[0]),
            RewardsDistributor(_c.rewardsDistributors[1]),
            RewardsDistributor(_c.rewardsDistributors[2])
        ];
        rewardsTokens = [
            MockERC20(_c.rewardsTokens[0]),
            MockERC20(_c.rewardsTokens[1]),
            MockERC20(_c.rewardsTokens[2])
        ];
        rewardsSender = _c.rewardsSender;

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

        // Make sure we can create locks of any duration
        vm.warp(block.timestamp + _maxTime);
    }

    function vote(
        uint256 _seedAddr,
        uint8[COUNT] memory _gaugeSeeds,
        uint64[COUNT] memory _weights
    ) public {
        address[] memory _delegateesWithPower = getDelegateesWithPower();
        if (_delegateesWithPower.length == 0) return;

        _seedAddr = _bound(_seedAddr, 0, _delegateesWithPower.length - 1);
        address sender = _delegateesWithPower[_seedAddr];

        bool[COUNT] memory used;
        uint256 count = 0;

        IGaugeVote.GaugeVote[] memory votes = new IGaugeVote.GaugeVote[](_gaugeSeeds.length);
        for (uint256 i = 0; i < _gaugeSeeds.length; i++) {
            uint256 index = uint256(_gaugeSeeds[i]) % gauges.length;
            _weights[i] = uint64(_bound(_weights[i], 1, type(uint64).max));

            address gauge = gauges[index];
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
        vm.assume(ivotesAdapter.getVotes(sender) > 0);

        vm.prank(sender);
        voter.vote(votes);
    }

    function setDelegateAddress(uint256 _delegatorIdx, uint256 _delegateeIdx) public {
        address delegator = _getAddress(_delegatorIdx);
        address delegatee = _getDelegatee(_delegateeIdx);

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
        address newDelegatee = _getDelegatee(_delegateeSeed);
        address currentDelegatee = ivotesAdapter.delegates(msgSender);

        _transitionIfTooOld(newDelegatee);
        _transitionIfTooOld(currentDelegatee);

        uint256[] memory tokens = _fromSetToArray(ownedTokens[msgSender]);

        // `delegate(address)` only re-delegates everything when auto-delegation is
        // enabled.  With the flag set it undelegates the currently delegated tokens and
        // stops there, so snapshot the delegated ones before the call.
        bool autoDelegationOff = ivotesAdapter.autoDelegationDisabled(msgSender);
        bool[] memory wasDelegated = new bool[](tokens.length);
        bool[] memory isExpired = new bool[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            wasDelegated[i] = ivotesAdapter.tokenIsDelegated(tokens[i]);
            isExpired[i] = escrow.isLockExpiredAtNextCheckpoint(tokens[i]);
        }

        vm.prank(msgSender);
        ivotesAdapter.delegate(newDelegatee);

        // Ghost state variables
        for (uint256 i = 0; i < tokens.length; i++) {
            if (wasDelegated[i] && currentDelegatee != address(0)) {
                _updateDelegationState(tokens[i], msgSender, Action.REMOVE, currentDelegatee);
            }
            // `delegate(address)` skips tokens that are expired at the next checkpoint
            if (!autoDelegationOff && newDelegatee != address(0) && !isExpired[i]) {
                _updateDelegationState(tokens[i], msgSender, Action.ADD, newDelegatee);
            }
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
        _assumeNonExpired(tokens);

        _transitionIfTooOld(delegatee);
        vm.prank(msgSender);
        ivotesAdapter.delegate(tokens);

        // Ghost state variables
        for (uint256 i = 0; i < tokens.length; i++) {
            _updateDelegationState(tokens[i], msgSender, Action.ADD, address(0));
        }
    }

    function undelegate(
        uint256 _jumpSeed,
        uint256 _senderSeed,
        uint256 _numToUndelegateSeed
    ) public adjustTimestamp(_jumpSeed) {
        address msgSender = _getAddress(_senderSeed);
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

        // Ghost state variables
        for (uint256 i = 0; i < tokens.length; i++) {
            _updateDelegationState(tokens[i], msgSender, Action.REMOVE, address(0));
        }
    }

    function createLock(
        uint256 _jumpSeed,
        uint256 _value,
        uint256 _duration,
        uint256 _senderSeed
    ) external adjustTimestamp(_jumpSeed) returns (uint256 tokenId) {
        _value = _bound(_value, escrow.minDeposit(), type(uint96).max);
        _value = getFlooredAmount(_value);
        vm.assume(_value > 0);
        _duration = _bound(_duration, 1 weeks, maxTime);
        _duration = getFlooredDuration(_duration);
        address msgSender = _getAddress(_senderSeed);
        address delegatee = ivotesAdapter.delegates(msgSender);

        _transitionIfTooOld(delegatee);

        // mint tokens to sender and approve to escrow
        // so escrow can transfer it from sender.
        token.mint(msgSender, _value);
        vm.startPrank(msgSender);
        token.approve(address(escrow), _value);
        tokenId = escrow.createLock(_value, _duration);
        vm.stopPrank();

        // Ghost state variables
        totalLocked += _value;
        activeTokenIds.add(tokenId);
        ownedTokens[msgSender].add(tokenId);

        _updateDelegationState(tokenId, msgSender, Action.ADD, address(0));

        return tokenId;
    }

    function lockPermanent(
        uint256 _jumpSeed,
        uint256 _ownerTokenId,
        uint256 _senderSeed
    ) external adjustTimestamp(_jumpSeed) {
        address msgSender = _getAddress(_senderSeed);
        address delegatee = ivotesAdapter.delegates(msgSender);
        _transitionIfTooOld(delegatee);

        if (ownedTokens[msgSender].length() == 0) return;

        _ownerTokenId = _bound(_ownerTokenId, 0, ownedTokens[msgSender].length() - 1);
        uint256 tokenId = ownedTokens[msgSender].at(_ownerTokenId);
        vm.assume(!isPermanentLock[tokenId]);
        vm.assume(!escrow.isLockExpiredAtNextCheckpoint(tokenId));

        vm.startPrank(msgSender);
        escrow.lockPermanent(tokenId);
        vm.stopPrank();

        // Ghost state variables
        isPermanentLock[tokenId] = true;
    }

    function unlockPermanent(
        uint256 _jumpSeed,
        uint256 _ownerTokenId,
        uint256 _senderSeed
    ) external adjustTimestamp(_jumpSeed) {
        address msgSender = _getAddress(_senderSeed);
        address delegatee = ivotesAdapter.delegates(msgSender);
        _transitionIfTooOld(delegatee);

        if (ownedTokens[msgSender].length() == 0) return;

        _ownerTokenId = _bound(_ownerTokenId, 0, ownedTokens[msgSender].length() - 1);
        uint256 tokenId = ownedTokens[msgSender].at(_ownerTokenId);
        vm.assume(isPermanentLock[tokenId]);

        vm.startPrank(msgSender);
        escrow.unlockPermanent(tokenId);
        vm.stopPrank();

        // Ghost state variables
        isPermanentLock[tokenId] = false;
    }

    function increaseAmount(
        uint256 _jumpSeed,
        uint256 _ownerTokenId,
        uint256 _value,
        uint256 _senderSeed
    ) external adjustTimestamp(_jumpSeed) {
        _value = _bound(_value, escrow.minDeposit(), type(uint96).max);
        _value = getFlooredAmount(_value);
        vm.assume(_value > 0);
        address msgSender = _getAddress(_senderSeed);
        address delegatee = ivotesAdapter.delegates(msgSender);
        _transitionIfTooOld(delegatee);

        if (ownedTokens[msgSender].length() == 0) return;

        _ownerTokenId = _bound(_ownerTokenId, 0, ownedTokens[msgSender].length() - 1);
        uint256 tokenId = ownedTokens[msgSender].at(_ownerTokenId);
        vm.assume(!escrow.isLockExpiredAtNextCheckpoint(tokenId));

        // mint tokens to sender and approve to escrow
        // so escrow can transfer it from sender.
        token.mint(msgSender, _value);
        vm.startPrank(msgSender);
        token.approve(address(escrow), _value);
        escrow.increaseAmount(tokenId, _value);
        vm.stopPrank();

        totalLocked += _value;
    }

    function increaseUnlockTime(
        uint256 _jumpSeed,
        uint256 _ownerTokenId,
        uint256 _duration,
        uint256 _senderSeed
    ) external adjustTimestamp(_jumpSeed) {
        address msgSender = _getAddress(_senderSeed);
        address delegatee = ivotesAdapter.delegates(msgSender);
        _transitionIfTooOld(delegatee);

        if (ownedTokens[msgSender].length() == 0) return;

        _ownerTokenId = _bound(_ownerTokenId, 0, ownedTokens[msgSender].length() - 1);
        uint256 tokenId = ownedTokens[msgSender].at(_ownerTokenId);
        vm.assume(!isPermanentLock[tokenId]);
        vm.assume(!escrow.isLockExpiredAtNextCheckpoint(tokenId));
        uint256 virtualStart = escrow.locked(tokenId).start;
        uint256 currentDuration = virtualStart + maxTime - clock.nextCheckpointTs();
        vm.assume(currentDuration + 1 weeks <= maxTime);
        _duration = _bound(_duration, currentDuration + 1 weeks, maxTime);
        _duration = getFlooredDuration(_duration);

        vm.startPrank(msgSender);
        escrow.increaseUnlockTime(tokenId, _duration);
        vm.stopPrank();
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
        _to = _from == _to ? (_to + 1) % len : _to;

        uint256 fromId = ownedTokens[msgSender].at(_from);
        uint256 toId = ownedTokens[msgSender].at(_to);

        {
            ILockedBalanceIncreasing.LockedBalance memory fromLocked = escrow.locked(fromId);
            ILockedBalanceIncreasing.LockedBalance memory toLocked = escrow.locked(toId);

            vm.assume(escrow.canMerge(fromLocked, toLocked));

            _transitionIfTooOld(delegatee);
        }

        bool isFromTokenDelegated = ivotesAdapter.tokenIsDelegated(fromId);

        vm.prank(msgSender);
        escrow.merge(fromId, toId);

        // Ghost state variables
        ownedTokens[msgSender].remove(fromId);
        activeTokenIds.remove(fromId);

        _updateDelegationState(fromId, msgSender, Action.REMOVE, address(0));

        // If from was delegated and merged into to, to becomes delegated
        if (isFromTokenDelegated) {
            _updateDelegationState(toId, msgSender, Action.ADD, address(0));
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
        _transitionIfTooOld(delegatee);

        if (ownedTokens[msgSender].length() == 0) return;

        _from = _bound(_from, 0, ownedTokens[msgSender].length() - 1);
        uint256 fromId = ownedTokens[msgSender].at(_from);
        uint256 currentAmount = escrow.locked(fromId).amount;
        uint256 minDeposit = escrow.minDeposit();

        // Ensure that after split, both tokens have more than `minDeposit`.
        if (currentAmount < 2 * minDeposit) return;

        _value = _bound(_value, minDeposit, currentAmount - minDeposit);
        _value = getFlooredAmount(_value);
        vm.assume(_value > 0);
        bool isFromTokenDelegated = ivotesAdapter.tokenIsDelegated(fromId);

        vm.prank(msgSender);
        uint256 newTokenId = escrow.split(fromId, _value);

        // Ghost state variables
        ownedTokens[msgSender].add(newTokenId);
        activeTokenIds.add(newTokenId);
        if (isPermanentLock[fromId]) isPermanentLock[newTokenId] = true;

        // split causes new token id to be minted. If `from` token
        // was delegated, then automatically delegated a newly created token.
        if (isFromTokenDelegated) {
            _updateDelegationState(newTokenId, msgSender, Action.ADD, address(0));
        }
    }

    function withdraw(uint256 _jumpSeed, uint256 _tokenIdSeed) public adjustTimestamp(_jumpSeed) {
        uint256[] memory ids = getActiveTokenIds();
        if (ids.length == 0) return;

        // Permanent locks are not withdrawable until they are unlocked, so only
        // consider the rest.
        uint256[] memory candidates = new uint256[](ids.length);
        uint256 count = 0;
        for (uint256 i = 0; i < ids.length; i++) {
            if (!isPermanentLock[ids[i]]) candidates[count++] = ids[i];
        }
        if (count == 0) return;

        uint256 tokenId = candidates[_bound(_tokenIdSeed, 0, count - 1)];
        ILockedBalanceIncreasing.LockedBalance memory locked = escrow.locked(tokenId);
        address owner = lockNft.ownerOf(tokenId);

        // Withdrawals are only allowed once the lock has expired.
        uint256 end = locked.start + maxTime;
        if (block.timestamp < end) vm.warp(end + 1);

        address delegatee = ivotesAdapter.delegates(owner);
        _transitionIfTooOld(delegatee);

        vm.prank(owner);
        escrow.withdraw(tokenId);

        // Ghost state variables
        totalLocked -= locked.amount;
        activeTokenIds.remove(tokenId);
        ownedTokens[owner].remove(tokenId);
        isPermanentLock[tokenId] = false;

        if (delegatee != address(0)) {
            _updateDelegationState(tokenId, owner, Action.REMOVE, delegatee);
        }
    }

    function createLockFor(
        uint256 _jumpSeed,
        uint256 _value,
        uint256 _duration,
        uint256 _senderSeed,
        uint256 _toSeed
    ) external adjustTimestamp(_jumpSeed) returns (uint256 tokenId) {
        _value = _bound(_value, escrow.minDeposit(), type(uint96).max);
        _value = getFlooredAmount(_value);
        vm.assume(_value > 0);
        _duration = _bound(_duration, 1 weeks, maxTime);
        _duration = getFlooredDuration(_duration);

        address funder = _getAddress(_senderSeed);
        address to = _getAddress(_toSeed);
        address delegatee = ivotesAdapter.delegates(to);

        _transitionIfTooOld(delegatee);

        token.mint(funder, _value);
        vm.startPrank(funder);
        token.approve(address(escrow), _value);
        tokenId = escrow.createLockFor(_value, _duration, to);
        vm.stopPrank();

        // Ghost state variables
        totalLocked += _value;
        activeTokenIds.add(tokenId);
        ownedTokens[to].add(tokenId);

        _updateDelegationState(tokenId, to, Action.ADD, address(0));

        return tokenId;
    }

    function setAutoDelegationDisabled(uint256 _senderSeed, bool _disabled) public {
        address msgSender = _getAddress(_senderSeed);
        vm.prank(msgSender);
        ivotesAdapter.setAutoDelegationDisabled(_disabled);
    }

    function transfer(
        uint256 _jumpSeed,
        uint192 _fromSeed,
        uint192 _toSeed
    ) public adjustTimestamp(_jumpSeed) {
        (address from, uint256 tokenId) = getUserWithToken(_fromSeed);
        if (from == address(0)) return;

        // Select `to` from remaining users (excluding `from`)
        address to;
        for (uint256 i = 0; i < COUNT; i++) {
            uint256 idx = (_toSeed + i) % 5;
            if (actors[idx] != from) {
                to = actors[idx];
                break;
            }
        }

        if (to == address(0)) return;
        if (from == to) return;

        address fromDelegatee = ivotesAdapter.delegates(from);
        address toDelegatee = ivotesAdapter.delegates(to);
        _transitionIfTooOld(fromDelegatee);
        _transitionIfTooOld(toDelegatee);

        vm.prank(from);
        lockNft.transferFrom(from, to, tokenId);

        ownedTokens[from].remove(tokenId);
        ownedTokens[to].add(tokenId);

        if (fromDelegatee != address(0)) {
            _updateDelegationState(tokenId, from, Action.REMOVE, fromDelegatee);
        }

        if (toDelegatee != address(0)) {
            _updateDelegationState(tokenId, to, Action.ADD, toDelegatee);
        }
    }

    function checkpointTransition(
        uint256 _jumpSeed,
        uint256 _userSeed,
        uint256 _transitionCount
    ) public adjustTimestamp(_jumpSeed) {
        uint256 len = delegateesWithVpPower.length();
        if (len == 0) return;

        address delegatee = delegateesWithVpPower.at(_bound(_userSeed, 0, len - 1));
        // We don't allow _transitionCount to be 0.
        // more than 300 causes too much gas overhead,
        // so 300 is enough to test most cases.
        _transitionCount = _bound(_transitionCount, 1, 300);

        ivotesAdapter.checkpointTransition(delegatee, _transitionCount);
    }

    function reset(uint256 _jumpSeed, uint256 _userSeed) public adjustTimestamp(_jumpSeed) {
        uint256 len = delegateesWithVpPower.length();
        if (len == 0) return;

        address delegatee = delegateesWithVpPower.at(_bound(_userSeed, 0, len - 1));
        _transitionIfTooOld(delegatee);

        // These checks intentionally discard many cases. This is desirable because
        // we don’t want `reset` to be invoked excessively. Since `reset` is already
        // triggered during merge/split/createlock operations, calling it too often
        // directly would reduce the effectiveness of those resets in testing.
        // With high depths and runs, it still calls `voter.reset` below enough times.
        if (!voter.isVoting(delegatee)) return;
        if (!voter.votingActive()) return;

        vm.prank(delegatee);
        voter.reset();
    }

    // ======================== Rewards ===================

    function triggerRewards(uint256 _jumpSeed, uint256 _distributorSeed, uint256 _amount) public adjustTimestamp(_jumpSeed) {
        _amount = _bound(_amount, 1, 1_000_000 ether);
        _distributorSeed = _bound(_distributorSeed, 0, 2);
        RewardsDistributor distributor = rewardsDistributors[_distributorSeed];
        MockERC20 rewardsToken = rewardsTokens[_distributorSeed];

        rewardsToken.mint(address(distributor), _amount);

        assert(rewardsToken.balanceOf(address(distributor)) > distributor.tokenLastBalance());
        vm.prank(rewardsSender);
        distributor.checkpointToken();

        triggeredRewards[_distributorSeed] += _amount;
    }

    function claimDirectly(
        uint256 _jumpSeed,
        uint256 _ownerTokenId,
        uint256 _senderSeed,
        uint256 _distributorSeed
    )
        public adjustTimestamp(_jumpSeed)
    {
        address msgSender = _getAddress(_senderSeed);
        address delegatee = ivotesAdapter.delegates(msgSender);
        _transitionIfTooOld(delegatee);

        if (ownedTokens[msgSender].length() == 0) return;

        _ownerTokenId = _bound(_ownerTokenId, 0, ownedTokens[msgSender].length() - 1);
        uint256 tokenId = ownedTokens[msgSender].at(_ownerTokenId);

        _distributorSeed = _bound(_distributorSeed, 0, 2);
        RewardsDistributor distributor = rewardsDistributors[_distributorSeed];

        vm.prank(msgSender);
        distributor.claim(tokenId);
    }

    function claimManyDirectly(uint256 _jumpSeed, uint256 _senderSeed, uint256 _distributorSeed) public adjustTimestamp(_jumpSeed) {
        _distributorSeed = _bound(_distributorSeed, 0, 2);
        RewardsDistributor distributor = rewardsDistributors[_distributorSeed];

        address msgSender = _getAddress(_senderSeed);
        uint256[] memory ownerTokens = _fromSetToArray(ownedTokens[msgSender]);
        vm.prank(msgSender);
        distributor.claimMany(ownerTokens);
    }

    function claimThroughAggregator(
        uint256 _jumpSeed,
        uint256 _ownerTokenId,
        uint256 _senderSeed
    )
        public adjustTimestamp(_jumpSeed)
    {
        address msgSender = _getAddress(_senderSeed);
        address delegatee = ivotesAdapter.delegates(msgSender);
        _transitionIfTooOld(delegatee);

        if (ownedTokens[msgSender].length() == 0) return;

        _ownerTokenId = _bound(_ownerTokenId, 0, ownedTokens[msgSender].length() - 1);
        uint256 tokenId = ownedTokens[msgSender].at(_ownerTokenId);

        IRewardsDistributor[] memory distributors = new IRewardsDistributor[](3);
        for(uint256 i = 0; i < 3; i++) {
            distributors[i] = IRewardsDistributor(rewardsDistributors[i]);
        }

        vm.prank(msgSender);
        rewardsAggregator.claim(distributors, tokenId, 52);
    }

    function claimManyThroughAggregator(uint256 _jumpSeed, uint256 _senderSeed) public adjustTimestamp(_jumpSeed) {
        address msgSender = _getAddress(_senderSeed);
        address delegatee = ivotesAdapter.delegates(msgSender);
        _transitionIfTooOld(delegatee);

        if (ownedTokens[msgSender].length() == 0) return;
        uint256[] memory ownerTokens = _fromSetToArray(ownedTokens[msgSender]);

        IRewardsDistributor[] memory distributors = new IRewardsDistributor[](3);
        for(uint256 i = 0; i < 3; i++) {
            distributors[i] = IRewardsDistributor(rewardsDistributors[i]);
        }

        vm.prank(msgSender);
        rewardsAggregator.claimMany(distributors, ownerTokens, 52);
    }

    // ======================== Helper Functions ===================

    function getFlooredAmount(uint256 _amount) internal view returns (uint256) {
        return curve.getFlooredAmount(_amount);
    }

    function getFlooredDuration(uint256 _duration) internal view returns (uint256) {
        return _duration / checkpointInterval * checkpointInterval;
    }

    function _updateDelegationState(
        uint256 _token,
        address _owner,
        Action _action,
        address _delegatee
    ) private {
        if (_delegatee == address(0)) {
            _delegatee = ivotesAdapter.delegates(_owner);
        }

        if (_delegatee == address(0)) return;

        if (_action == Action.ADD) {
            incomingTokens[_delegatee].add(_token);
            outgoingTokens[_owner].add(_token);
            _updateDelegateeVotingPower(_delegatee);

            return;
        }

        if (_action == Action.REMOVE) {
            incomingTokens[_delegatee].remove(_token);
            outgoingTokens[_owner].remove(_token);
            _updateDelegateeVotingPower(_delegatee);

            return;
        }
    }

    function _updateDelegateeVotingPower(address _delegatee) private {
        if (ivotesAdapter.getVotes(_delegatee) > 0) {
            delegateesWithVpPower.add(_delegatee);
        } else {
            delegateesWithVpPower.remove(_delegatee);
        }
    }

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
    ) public pure returns (uint256[] memory) {
        if (_tokenIds.length == 0) return new uint256[](0);

        uint256 numToDelegate = _bound(_seed, 1, _tokenIds.length);
        uint256[] memory newTokens = new uint256[](numToDelegate);
        for (uint256 i = 0; i < numToDelegate; i++) {
            newTokens[i] = _tokenIds[i];
        }

        return newTokens;
    }

    function getUserWithToken(uint192 _seed) public view returns (address, uint256) {
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

    /// @dev Like `_getAddress`, but sometimes returns `address(0)` so that
    ///      `delegate(address(0))` and `setDelegateAddress(address(0))` gets coverage.
    function _getDelegatee(uint256 _seedAddr) private view returns (address) {
        _seedAddr = _bound(_seedAddr, 0, actors.length);
        return _seedAddr == actors.length ? address(0) : actors[_seedAddr];
    }

    function _assumeNonExpired(address _sender) internal view {
        uint256[] memory tokenIds = VotingEscrow(escrow).ownedTokens(_sender);
        _assumeNonExpired(tokenIds);
    }

    function _assumeNonExpired(uint256[] memory _tokenIds) internal view {
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            vm.assume(!escrow.isLockExpiredAtNextCheckpoint(_tokenIds[i]));
        }
    }

    // The checkpoint functions in the Escrow and EscrowIVotesAdapter are designed such that
    // When a new token is created/merged/split/withdrawal/delegate/undelegated, it first
    // finds the last global point and starts looping from it on week duration (possibly till current time)
    // to update bias on each week. Such design ensures that total supply can be calculated on chain
    // and not result in out of gas error. In the loops, we use `255` which is the maximum
    // number of weeks it can fill in before the last point and the new point. Note that
    // if last point was created for more than 254.00..1 weeks ago, this can result
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
        if (_delegatee == address(0)) return;

        uint256 latestPointIndex = ivotesAdapter.latestPointIndex(_delegatee);

        (, , uint256 writtenTs) = ivotesAdapter.pointHistory(_delegatee, latestPointIndex);
        if (block.timestamp < writtenTs) return;
        uint256 lastPointCheckpointDiff = (block.timestamp - writtenTs) / checkpointInterval;
        if (lastPointCheckpointDiff >= 254) {
            ivotesAdapter.checkpointTransition(_delegatee, lastPointCheckpointDiff + 1);
        }
    }
}
