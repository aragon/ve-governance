pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {console2 as console} from "forge-std/console2.sol";

// aragon contracts
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig, MultisigSetup} from "@aragon/multisig/MultisigSetup.sol";

import {MockPluginSetupProcessor} from "@mocks/osx/MockPSP.sol";
import {MockDAOFactory} from "@mocks/osx/MockDAOFactory.sol";
import {MockERC20} from "@mocks/MockERC20.sol";

import "@helpers/OSxHelpers.sol";

import {IEscrowCurveTokenStorage} from "@escrow-interfaces/IEscrowCurveIncreasing.sol";
import {IWithdrawalQueueErrors} from "src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol";
import {IGaugeVote} from "src/voting/ISimpleGaugeVoter.sol";
import {VotingEscrow, QuadraticIncreasingEscrow, ExitQueue, GaugeDistributorVoter, GaugeDistributorVoterSetup, ISimpleGaugeVoterSetupParams} from "src/voting/GaugeDistributorVoterSetup.sol";

import {GaugeVotingBase} from "./GaugeDistributorBase.sol";

contract TestGaugeIncentivesDistribution is GaugeVotingBase {
    uint256[] ids;
    GaugeVote[] votes;

    address owner = address(0x420);
    uint256 lockDeposit = 1000 ether;
    uint256 tokenId;
    address gauge = address(0x777);

    uint time;

    function _increaseTime(uint _by) internal {
        time += _by;
        vm.warp(time);
    }

    function setUp() public override {
        super.setUp();

        // reset clock
        vm.warp(0);
        time = block.timestamp;

        // means we have voting power
        curve.setWarmupPeriod(0);

        // mint underlying and stake
        token.mint(owner, lockDeposit);
        vm.startPrank(owner);
        {
            token.approve(address(escrow), lockDeposit);
            tokenId = escrow.createLock(lockDeposit);
        }
        vm.stopPrank();

        // activate cp & warp to an active window
        _increaseTime(2 weeks + 1 hours + 1);

        assertGt(escrow.votingPower(tokenId), 0);
        assertTrue(voter.votingActive(), "voting should be active");

        // create a gauge
        voter.createGauge(gauge, "metadata");
    }

    function testSingleVote(uint128 _weight) public {
        vm.assume(_weight > 0);

        // create the vote
        votes.push(GaugeVote(_weight, gauge));

        uint votingPower = escrow.votingPower(tokenId);

        // vote
        vm.startPrank(owner);
        {
            vm.expectEmit(true, true, true, true);
            emit Voted({
                voter: owner,
                gauge: gauge,
                epoch: voter.epochId(),
                tokenId: tokenId,
                votingPowerCastForGauge: votingPower,
                totalVotingPowerInGauge: votingPower,
                totalVotingPowerInContract: votingPower,
                timestamp: block.timestamp
            });
            voter.vote(tokenId, votes);
        }
        vm.stopPrank();

        // global state
        uint256 _totalVotingPower = voter.totalVotingPowerCast();
        uint256 _gaugeVotingPower = voter.gaugeVotes(gauge);

        // activate cp & warp to an active window
        _increaseTime(1 weeks + 1 hours + 1);

        // should now be inactive (we don't test this part herewe have the epoch logic tests)
        vm.assume(!voter.votingActive());
        token.mint(address(dao), 10 ether);
        console.log(gauge);
        uint256 _gaugeBalancePre = token.balanceOf(gauge);
        voter.claimIncentives(gauge, address(token));
        uint256 _gaugeBalancePost = token.balanceOf(gauge);
        assertTrue(_gaugeBalancePost > _gaugeBalancePre, "Gauge balance should've increased");

        // Check the actual payout of the gauge is the correct
        // assertEq(_gaugeBalancePost == )
    }
}
