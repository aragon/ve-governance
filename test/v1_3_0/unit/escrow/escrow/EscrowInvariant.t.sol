pragma solidity ^0.8.17;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {EscrowBase} from "../../../base/EscrowBase.sol";

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
    VotingEscrow
} from "../../../versions.sol";
import {IERC721EnumerableMintableBurnable as IERC721EMB} from "@lock/IERC721EMB.sol";

import {StdInvariant} from "forge-std/StdInvariant.sol";

contract TestBlax is IEscrowCurveTokenStorage, EscrowBase {
    Handler internal h;

    function setUp() public override {
        super.setUp();

        escrow.setMinDeposit(100);
        escrow.enableSplit();

        h = new Handler(
            address(escrow),
            address(nftLock),
            address(ivotesAdapter),
            curve.maxTime(),
            clock.checkpointInterval()
        );

        //  targetContract(address(ivotesAdapter));
        targetContract(address(h));

        {
            bytes4[] memory selectors = new bytes4[](5);
            selectors[0] = Handler.createLock.selector;
            selectors[1] = Handler.merge.selector;
            selectors[2] = Handler.split.selector;
            selectors[3] = Handler.setDelegateAddress.selector;
            selectors[4] = Handler.delegate.selector;
            FuzzSelector memory a = FuzzSelector(address(h), selectors);

            targetSelector(a);
        }
    }

    function invariant_TotalLockedCorrect() public {
        assertEq(h.totalLocked(), escrow.totalLocked());
    }

    function invariant_TokenBalanceEqualsTotalLocked() public {
        assertEq(MockERC20(escrow.token()).balanceOf(address(escrow)), escrow.totalLocked());
    }

    function invariant_SumOfNftsAmountsEqualTotalLocked() public {
        uint256 amountSum = 0;
        uint256 vpSum = 0;

        uint256 globalPower = escrow.totalVotingPower();
        uint256 lastId = escrow.lastLockId();

        uint256[] memory ids = h.getActiveTokenIds();
        for (uint256 i = 0; i < ids.length; i++) {
            uint256 tokenId = ids[i];

            uint256 vp = escrow.votingPower(tokenId);
            uint256 amount = escrow.locked(tokenId).amount;

            amountSum += amount;
            vpSum += vp;
        }

        assertEq(amountSum, escrow.totalLocked(), "Sum of NFTs != totalLocked");
        // assertEq(vpSum, escrow.totalVotingPower(), "Sum of vps individually != total vp");
    }


    // giorgi delegated to alice but no tokens, just setDelegateAddress
    // charlie delegated to alice and gave her token.

    // loop starts, we get giorgi. 
    function invariant_fuck() public {
        address[] memory actors = h.getActors();

        uint256 totalVp = 0;

        for(uint256 i = 0; i < actors.length; i++) {
            address actor = actors[i];
            
            uint256[] memory userIncomingTokens = h.getActorDelegateeTokens(actor);
            uint256[] memory userOutgoingTokens = h.getActorDelegatedTokens(actor);

            uint256 userVp = 0;
            assertEq(userOutgoingTokens.length, ivotesAdapter.numberOfDelegatedTokens(actor));

            for(uint256 j = 0; j < userIncomingTokens.length; j++) {
                assertTrue(ivotesAdapter.tokenIsDelegated(userIncomingTokens[j]));
                userVp += escrow.votingPower(userIncomingTokens[j]);
            }

            assertApproxEqAbs(userVp, ivotesAdapter.getPastVotes(actor, block.timestamp), userIncomingTokens.length);
        }

    //     0x0000000000000000000000000000000000000012 delegates to 0x0000000000000000000000000000000000000011
    //     0x000000000000000000000000000000000000000A delegates to 0x0000000000000000000000000000000000000011

    //      0x0000000000000000000000000000000000000012 calls createLock. 

    //      actorDelegatedTokens[0x0000000000000000000000000000000000000012] = [5]

    //    actor = 0x000000000000000000000000000000000000000A and get this actor's delegated token.
    //    clearly 0.

        // assertEq(totalVp, ivotesAdapter.getPastTotalSupply(block.timestamp));
    }
}

contract Handler is Test {
    using EnumerableSet for EnumerableSet.UintSet;

    IERC721EMB private lockNft;
    VotingEscrow private escrow;
    EscrowIVotesAdapter private ivotesAdapter;

    MockERC20 private token;
    uint256 private maxTime;
    uint256 private checkpointInterval;

    // ghost variables
    address[] public actors;
    mapping(address => uint256[]) public actorTokens;


    mapping(address => EnumerableSet.UintSet) internal actorDelegatedTokens;
    mapping(address => EnumerableSet.UintSet) internal actorDelegateeTokens;


    uint256 public totalLocked;

    // Active tokenIds..
    EnumerableSet.UintSet internal activeTokenIds;
    

    constructor(address _escrow, address _lockNft, address _ivotesAdapter, uint256 _maxTime, uint256 _checkpointInterval) {
        escrow = VotingEscrow(_escrow);
        lockNft = IERC721EMB(_lockNft);
        token = MockERC20(escrow.token());
        ivotesAdapter = EscrowIVotesAdapter(_ivotesAdapter);

        maxTime = _maxTime;
        checkpointInterval = _checkpointInterval;

        // create 10 actors.
        for (uint256 i = 10; i <= 20; i++) {
            actors.push(address(uint160(i)));
        }
    }

    function setDelegateAddress(uint256 _delegatorIdx, uint256 _delegateeIdx) public  {
        address delegator = _getSender(_delegatorIdx);
        address delegatee = _getSender(_delegateeIdx);
        console.log("delegation timestamp", block.timestamp);
        console.log("Delegator/delegatee", delegator, delegatee);

        if(ivotesAdapter.numberOfDelegatedTokens(delegator) != 0) {
            return;
        }

        // ivotesAdapter.

        vm.prank(delegator);
        ivotesAdapter.setDelegateAddress(delegatee);
    }

    function delegate(uint256 _seedAddr) public {
        address msgSender = _getSender(_seedAddr);
        address delegatee = ivotesAdapter.delegates(msgSender);

        if(actorTokens[msgSender].length == 0 || delegatee == address(0)) {
            return;
        }

        uint256[] memory tokens = actorTokens[msgSender];
        uint256[] memory temp = new uint256[](tokens.length);
        uint256 count = 0;

        for (uint256 i = 0; i < tokens.length; ++i) {
            if(!ivotesAdapter.tokenIsDelegated(tokens[i])) {
                temp[count] = tokens[i];
                count++;
            }
        }

        if(count == 0) return;

        uint256[] memory newTokens = new uint256[](count);
        for (uint256 i = 0; i < count; ++i) {
            newTokens[i] = temp[i];
        }

        vm.prank(msgSender);
        ivotesAdapter.delegate(newTokens);

        for(uint256 i = 0; i < newTokens.length; i++) {
            actorDelegateeTokens[delegatee].add(newTokens[i]);
            actorDelegatedTokens[msgSender].add(newTokens[i]);
        }
    }

    function createLock(
        uint256 _jumpSeed,
        uint256 _value,
        uint256 _seedAddr
    ) external adjustTimestamp(_jumpSeed) returns (uint256) {
        _value = bound(_value, escrow.minDeposit(), type(uint96).max);
        address msgSender = _getSender(_seedAddr);

        console.log("create lock timestamp", block.timestamp);
        console.log(msgSender);

        // mint tokens to sender and approve to escrow 
        // so escrow can transfer it from sender.
        token.mint(msgSender, _value);
        vm.startPrank(msgSender);
        token.approve(address(escrow), _value);
        uint256 tokenId = escrow.createLock(_value);
        vm.stopPrank();

        totalLocked += _value;
        activeTokenIds.add(tokenId);

        actorTokens[msgSender].push(tokenId);

        // If sender has a delegatee already set, 
        // tokenId automatically gets delegated.
        address delegatee = ivotesAdapter.delegates(msgSender);
        if(delegatee != address(0)) {
            actorDelegateeTokens[delegatee].add(tokenId);
            actorDelegatedTokens[msgSender].add(tokenId);
        }
    }

    function merge(
        uint256 _jumpSeed,
        uint256 _from,
        uint256 _to,
        uint256 _seedAddr
    ) external adjustTimestamp(_jumpSeed) {
        address msgSender = _getSender(_seedAddr);

        uint256 len = actorTokens[msgSender].length;
        if (len < 2) return;
    
        _from = bound(_from, 0, len - 1);
        _to = bound(_to, 0, len - 1);

        _to = _from == _to ? (_to + 1) % len : _to;

        uint256 fromId = actorTokens[msgSender][_from];
        uint256 toId = actorTokens[msgSender][_to];

        {
            ILockedBalanceIncreasing.LockedBalance memory fromLocked = escrow.locked(fromId);
            ILockedBalanceIncreasing.LockedBalance memory toLocked = escrow.locked(toId);

            // Starts not equal and one of the token is not mature or both.
            if(!escrow.canMerge(fromLocked, toLocked)) {
                uint256 fromEnd = fromLocked.start + maxTime;
                uint256 toEnd = toLocked.start + maxTime;

                if(fromEnd >= block.timestamp || toEnd >= block.timestamp) {
                    uint256 biggerTs = fromEnd > toEnd ? fromEnd : toEnd;
                    vm.warp(biggerTs + 1);
                }
            }
        }

        vm.prank(msgSender);
        escrow.merge(fromId, toId);

        // delete `from` element
        actorTokens[msgSender][_from] = actorTokens[msgSender][len - 1];
        actorTokens[msgSender].pop();

        // delete _from from `activeTokenIds`
        activeTokenIds.remove(fromId);

        // remove so `fromId` is not delegated anymore.
        address delegatee = ivotesAdapter.delegates(msgSender);
        if(delegatee != address(0)) {
            actorDelegateeTokens[delegatee].remove(fromId);
            actorDelegatedTokens[msgSender].remove(fromId);
        }
    }

    function split(
        uint256 _jumpSeed,
        uint256 _from,
        uint256 _value,
        uint256 _seedAddr
    ) public adjustTimestamp(_jumpSeed) {
        address msgSender = _getSender(_seedAddr);
        if (actorTokens[msgSender].length == 0) return;

        _from = bound(_from, 0, actorTokens[msgSender].length - 1);

        uint256 fromId = actorTokens[msgSender][_from];

        uint256 currentAmount = escrow.locked(fromId).amount;
        uint256 minDeposit = escrow.minDeposit();

        if (currentAmount == 1) return;
        if (currentAmount < 2 * minDeposit) return;

        _value = bound(_value, minDeposit, currentAmount - minDeposit);

        vm.prank(msgSender);
        uint256 newTokenId = escrow.split(fromId, _value);

        actorTokens[msgSender].push(newTokenId);
        activeTokenIds.add(newTokenId);

        // If sender has a delegatee already set, 
        // tokenId automatically gets delegated.
        address delegatee = ivotesAdapter.delegates(msgSender);

        if(delegatee != address(0)) {
            actorDelegateeTokens[delegatee].add(fromId);
            actorDelegatedTokens[msgSender].add(fromId);

            actorDelegateeTokens[delegatee].add(newTokenId);
            actorDelegatedTokens[msgSender].add(newTokenId);
        }
    }


    // ======================== Helper Functions ===================

    function getActors() public view returns(address[] memory) {
        return actors;
    }

    function getActorDelegateeTokens(address _account) public view returns(uint256[] memory) {
        return _fromSetToArray(actorDelegateeTokens[_account]);
    }

    function getActorDelegatedTokens(address _account) public view returns(uint256[] memory) {
        return _fromSetToArray(actorDelegatedTokens[_account]);
    }

    function getActiveTokenIds() public view returns (uint256[] memory) {
        return _fromSetToArray(activeTokenIds);
    }

    function _fromSetToArray(EnumerableSet.UintSet storage _set) private view returns(uint256[] memory) {
        uint256 length = _set.length();
        uint256[] memory ids = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            ids[i] = _set.at(i);
        }

        return ids;
    }

    modifier adjustTimestamp(uint256 timeJumpSeed) {
        uint256 timeJump = _bound(timeJumpSeed, 2 minutes, 40 days);
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
        return actors[bound(_seedAddr, 0, actors.length - 1)];
    }

    
}
