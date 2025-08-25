pragma solidity ^0.8.17;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {EscrowBase} from "../base/EscrowBase.sol";

import {console2 as console} from "forge-std/console2.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig, MultisigSetup} from "@aragon/multisig/src/MultisigSetup.sol";
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

        uint256[] memory ids = h.getActiveTokenIds();
        for (uint256 i = 0; i < ids.length; i++) {
            uint256 tokenId = ids[i];

            uint256 vp = escrow.votingPower(tokenId);
            uint256 amount = escrow.locked(tokenId).amount;

            amountSum += amount;
            vpSum += vp;
        }

        assertEq(amountSum, escrow.totalLocked(), "Sum of NFT Amoutns != totalLocked");
        assertApproxEqAbs(
            vpSum,
            escrow.totalVotingPower(),
            ids.length,
            "Sum of vps individually != total vp"
        );
    }

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

    function invariant_UserCannotHaveMoreVotesOnGaugeVoterThanIVotesAdapter() public {
        address[] memory actors = h.getActors();

        uint256 totalPastVotes = 0;
        uint256 delta = 0;
        for (uint256 i = 0; i < actors.length; i++) {
            address actor = actors[i];

            uint256 pastVotes = ivotesAdapter.getVotes(actor);
            totalPastVotes += pastVotes;
            assertLe(voter.usedVotingPower(actor), pastVotes);

            delta += h.getIncomingTokens(actor).length;
        }

        uint256 totalOnGaugeVoter = voter.totalVotingPowerCast();
        if (totalOnGaugeVoter > totalPastVotes) {
            assertApproxEqAbs(totalOnGaugeVoter, totalPastVotes, delta);
        }
    }

    function invariant_TotalVotingPowerDoesNotExceedTotalLocked() public {
        assertLe(escrow.totalVotingPower(), bias(h.totalLocked(), maxTime));
    }
}
