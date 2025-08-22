pragma solidity ^0.8.17;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {EscrowBase} from "../base/EscrowBase.sol";

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
} from "../versions.sol";
import {IERC721EnumerableMintableBurnable as IERC721EMB} from "@lock/IERC721EMB.sol";

import {StdInvariant} from "forge-std/StdInvariant.sol";

import {DelegationHandler} from "./handlers/DelegationHandler.sol";

contract TestDelegationInvariant is IEscrowCurveTokenStorage, EscrowBase {
    DelegationHandler internal h;

    function setUp() public override {
        super.setUp();

        escrow.setMinDeposit(100);
        escrow.enableSplit();
        nftLock.enableTransfers();

        h = new DelegationHandler(
            DelegationHandler.Contracts({
                escrow: address(escrow),
                curve: address(curve),
                lockNft: address(nftLock),
                ivotesAdapter: address(ivotesAdapter),
                queue: address(queue),
                voter: address(voter)
            }),
            address(this),
            curve.maxTime(),
            clock.checkpointInterval()
        );

        targetContract(address(h));

        {
            // @jordan big one missing imo is transfer
            bytes4[] memory selectors = new bytes4[](10);
            selectors[0] = DelegationHandler.createLock.selector;
            selectors[1] = DelegationHandler.merge.selector;
            selectors[2] = DelegationHandler.split.selector;
            selectors[3] = DelegationHandler.setDelegateAddress.selector;
            selectors[4] = DelegationHandler.delegate.selector;
            selectors[5] = DelegationHandler.delegateSpecificTokens.selector;
            selectors[6] = DelegationHandler.undelegate.selector;
            selectors[7] = DelegationHandler.withdraw.selector;
            selectors[8] = DelegationHandler.vote.selector;
            selectors[9] = DelegationHandler.transfer.selector;
            FuzzSelector memory a = FuzzSelector(address(h), selectors);

            targetSelector(a);
        }
    }

    // function invariant_TotalLockedCorrect() public {
    //     assertEq(h.totalLocked(), escrow.totalLocked());
    // }

    // function invariant_TokenBalanceEqualsTotalLocked() public {
    //     assertEq(MockERC20(escrow.token()).balanceOf(address(escrow)), escrow.totalLocked());
    // }

    // function invariant_SumOfNftsAmountsEqualTotalLocked() public {
    //     uint256 amountSum = 0;
    //     uint256 vpSum = 0;

    //     uint256 globalPower = escrow.totalVotingPower();
    //     uint256 lastId = escrow.lastLockId();

    //     uint256[] memory ids = h.getActiveTokenIds();
    //     for (uint256 i = 0; i < ids.length; i++) {
    //         uint256 tokenId = ids[i];

    //         uint256 vp = escrow.votingPower(tokenId);
    //         uint256 amount = escrow.locked(tokenId).amount;

    //         amountSum += amount;
    //         vpSum += vp;
    //     }
    //     // @jordan we may wish to ensure at least 1 veNFT was created

    //     assertEq(amountSum, escrow.totalLocked(), "Sum of NFT Amoutns != totalLocked");
    //     assertApproxEqAbs(
    //         vpSum,
    //         escrow.totalVotingPower(),
    //         ids.length,
    //         "Sum of vps individually != total vp"
    //     );
    // }

    function invariant_UserHasCorrectPastVotes() public {
        address[] memory actors = h.getActors();

        for (uint256 i = 0; i < actors.length; i++) {
            address actor = actors[i];

            uint256[] memory userIncomingTokens = h.getIncomingTokens(actor);
            uint256[] memory userOutgoingTokens = h.getOutgoingTokens(actor);

            uint256 userVp = 0;
            assertEq(userOutgoingTokens.length, ivotesAdapter.numberOfDelegatedTokens(actor));

            for (uint256 j = 0; j < userIncomingTokens.length; j++) {
                assertTrue(ivotesAdapter.tokenIsDelegated(userIncomingTokens[j]));
                userVp += escrow.votingPower(userIncomingTokens[j]);
            }

            assertApproxEqAbs(
                userVp,
                ivotesAdapter.getPastVotes(actor, block.timestamp),
                userIncomingTokens.length
            );
        }
    }

    // function invariant_UserCannotHaveMoreVotesOnGaugeVoterThanIVotesAdapter() public {
    //     address[] memory actors = h.getActors();

    //     uint256 totalPastVotes = 0;
    //     uint256 delta = 0;
    //     for (uint256 i = 0; i < actors.length; i++) {
    //         address actor = actors[i];

    //         uint256 pastVotes = ivotesAdapter.getVotes(actor);
    //         totalPastVotes += pastVotes;
    //         assertLe(voter.usedVotingPower(actor), pastVotes);

    //         delta += h.getIncomingTokens(actor).length;
    //     }

    //     uint256 totalOnGaugeVoter = voter.totalVotingPowerCast();
    //     if (totalOnGaugeVoter > totalPastVotes) {
    //         assertApproxEqAbs(totalOnGaugeVoter, totalPastVotes, delta);
    //     }
    // }

    // function invariant_TotalVotingPowerDoesNotExceedTotalLocked() public {
    //     assertLe(escrow.totalVotingPower(), bias(h.totalLocked(), maxTime));
    // }

    // @jordan: ideas:
    // sum of getPastVotes === totalSupply (delegate checkpointing === total supply checkpointing)
    // transfers don't affect the invariants
    // total voting power cannot exceed total locked * max multiplier

    function test_fail() public {
        // Call 1: createLock from 0xA7f11814BAfC2e39876a4Ed4d365e3a3e9464eeD
        h.createLock(0, 33720500611722038452979, 78245915442741988190677272574);

        // Call 2: createLock from 0x0000000000000000000000000000000000000622
        h.createLock(
            6416300434804439282460721299901958726,
            393112192,
            90601268499363008574934198218337222492552650963976820839
        );

        // Call 3: withdraw from 0xCabc3A65c1461fD7F0D918C77847B70C19CA504f
        h.withdraw(20952878174687691479, 44569603420927373392540);

        // Call 4: transfer from 0x0000000000000000000000000000000000002892
        h.transfer(
            183506396549288895472695117647628657675493887251,
            6277101735386680763835789423207666416102355444464034512894,
            59426794664697322831
        );

        // Call 5: setDelegateAddress from 0x0000000000000000000000000000000000001514
        h.setDelegateAddress(
            9199822180911064252824924492236298,
            115792089237316195423570985008687907853269984665640564039457584007913129639933
        );

        // Call 6: createLock from 0x0000000000000000000000000000000000001B23
        h.createLock(
            13,
            2834,
            115792089237316195423570985008687907853269984665561335876943319670319585689600
        );

        // Call 7: split from 0x0000000000000000000000000000000000002260
        h.split(
            975319357645590152925807897175830,
            115792089237316195423570985008687907853269984665640564039457584007913129639932,
            109868044136668890621783525868065771232320125296590373238084575229,
            160245507506002667413472673202689183682916305541
        );

        // Call 8: transfer from 0x00000000000000000000000000000000000004f2
        h.transfer(4, 15700, 1847);

        // Call 9: createLock from 0x0000000000000000000000000000000000001982
        h.createLock(18616, 7222, 14);

        // Call 10: split from 0xA9Cf019493bFd8d4Af682a7c6b7fF0716d8BcFdd
        h.split(
            729052926586223967172552294588020668132352480065112266109,
            8874289766722734562539000901337784751,
            18205,
            10582866330424665163163139054790471178913434135054697207566472
        );

        // Call 11: withdraw from 0x00000000000000000000000000000003B39F2596
        h.withdraw(15, 3);

        // Call 12: split from 0x00000000000000000000000000000000b5508aA8
        h.split(6659, 13, 8077, 17);

        // Call 13: createLock from 0xbEeB4e7b4a14C852DCd7bb2e4836Fa2103B814d3
        h.createLock(
            39095828447348713500765209219103608518058942178339766163017224860133752832026,
            3406,
            115792089237316195423570985008687907853269984665640564039457584007913129639842
        );

        // Call 14: createLock from 0x2dEb0f175Ec40DC19C5794D28731203225580cc4
        h.createLock(
            9352720881931647675843,
            17331978,
            9569513777769478719505580706270602968028617592513447163181231902697396322
        );

        // Call 15: createLock from 0x7Fb76ce24d35eBB94E26A20115E06BC55bD49B9c
        h.createLock(18, 17, 4);

        // Call 16: createLock from 0x0000000000000000000000000000000000000E63
        h.createLock(44, 676430690625556173441485485871, 562561971244002422);

        // Call 17: setDelegateAddress from 0x00000000000000000000000000000000000031A7
        h.setDelegateAddress(1, 17);

        // Call 18: createLock from 0x000000000000000000000000000000000005C974
        h.createLock(
            9518847204935358166548570266051330015907116135037852959641967396525866745855,
            13005,
            3
        );

        // Call 19: createLock from 0x63dfc1924d44703231A40FD1C9a350d667271cE0
        h.createLock(
            250891034131842512579383290831667302709997423753,
            2199800114093312501649909800289587561947486435006938230665734509,
            218889359220142796966068898261752739963177485584432126302753216458294404387
        );

        // Call 20: createLock from 0x0000000000000000000000000000000000000422
        h.createLock(1591950451627, 1985, 316352683190270858145487346339311415296123);

        // Call 21: createLock from 0xE4F096507D980f014cfe2DcE3Ab07808E5F4716B
        h.createLock(13, 17, 5931);

        // Call 22: createLock from 0x756666696369656E742062616C616E636520666E
        h.createLock(15788, 17, 19);

        // Call 23: createLock from 0x00000000000000000000000000000000000003D3
        h.createLock(1870234929058, 1, 1211455396487933891409610188980251468240681);

        // Call 24: transfer from 0x1264a11045c8c8CB0A0B69f7189306D995f2a24D
        h.transfer(
            2958196259308096332271674080555595781803645,
            157666846337738599259966093929606,
            315635414350
        );

        // Call 25: withdraw from 0x0000000000000000000000Bffc0c9DEC6a32C0d4
        h.withdraw(
            24690381164098606927622775960229780056890160002690428346511805760387206519918,
            19
        );

        // Call 26: createLock from 0x00000000000000000000000000000000330609E5
        h.createLock(14, 13879, 10);

        // Call 27: merge from 0x0000000000000000000000000000000000002986
        h.merge(
            4081050224648,
            2972635627036587676581235783278377323763123163353,
            5352729713,
            283089496346374249807151247117016378603440
        );

        address check = 0x000000000000000000000000000000000000000C;

        console.log("giorgi nice", ivotesAdapter.getPastVotes(check, block.timestamp));
    }
}
