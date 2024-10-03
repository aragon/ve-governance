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
import {VotingEscrow, QuadraticIncreasingEscrow, ExitQueue, SimpleGaugeVoter, SimpleGaugeVoterSetup, ISimpleGaugeVoterSetupParams} from "src/voting/SimpleGaugeVoterSetup.sol";

import {GaugeVotingBase} from "./GaugeVotingBase.sol";

contract TestGaugeManage is GaugeVotingBase {
    function setUp() public override {
        super.setUp();
        vm.warp(1); // avoids sentinel value for createdAt
    }

    // only gauge admins
    function testOnlyGaugeAdmins(address _notThis) public {
        vm.assume(_notThis != address(this));
        vm.assume(_notThis != address(dao));

        bytes memory err = _authErr({
            _caller: _notThis,
            _contract: address(voter),
            _perm: voter.GAUGE_ADMIN_ROLE()
        });

        vm.startPrank(_notThis);
        {
            // only gauge admins can create gauges
            vm.expectRevert(err);
            voter.createGauge(address(0), "");

            // only gauge admins can deactivate gauges
            vm.expectRevert(err);
            voter.deactivateGauge(address(0));

            // only gauge admins can activate gauges
            vm.expectRevert(err);
            voter.activateGauge(address(0));

            // only gauge admins can update gauge metadata
            vm.expectRevert(err);
            voter.updateGaugeMetadata(address(0), "");

            vm.expectRevert(err);
            voter.pause();

            vm.expectRevert(err);
            voter.unpause();
        }
        vm.stopPrank();
    }

    // emits the event and pushes the new gauge
    function testFuzz_CreateGauge(address _gauge, string calldata metadata) public {
        vm.assume(_gauge != address(0));
        vm.expectEmit(true, true, false, true);
        emit GaugeCreated(_gauge, address(this), metadata);
        voter.createGauge(_gauge, metadata);

        assertEq(voter.getAllGauges().length, 1);
        assertEq(voter.isActive(_gauge), true);
    }

    // can't create if exists alread
    function testFuzz_CreateGauge_Exists(address _gauge, string calldata metadata) public {
        vm.assume(_gauge != address(0));
        voter.createGauge(_gauge, metadata);
        vm.expectRevert(GaugeExists.selector);
        voter.createGauge(_gauge, metadata);
    }

    // can't decativate a non-existent gauge
    function testFuzz_DeactivateGauge(address _gauge) public {
        vm.expectRevert(abi.encodeWithSelector(GaugeDoesNotExist.selector, _gauge));
        voter.deactivateGauge(_gauge);
    }

    // can deactivate an existing gauge
    function testFuzz_DeactivateGaugeExists(address _gauge, string calldata metadata) public {
        vm.assume(_gauge != address(0));
        voter.createGauge(_gauge, metadata);
        vm.expectEmit(true, false, false, true);
        emit GaugeDeactivated(_gauge);
        voter.deactivateGauge(_gauge);

        assertEq(voter.getAllGauges().length, 1);
        assertEq(voter.isActive(_gauge), false);
    }

    // can't deactivate an already deactivated gauge
    function testFuzz_DeactivateGaugeAlreadyDeactivated(
        address _gauge,
        string calldata metadata
    ) public {
        vm.assume(_gauge != address(0));
        voter.createGauge(_gauge, metadata);
        voter.deactivateGauge(_gauge);
        vm.expectRevert(GaugeActivationUnchanged.selector);
        voter.deactivateGauge(_gauge);
    }

    // can't activate a non-existent gauge
    function testFuzz_ActivateGauge(address _gauge) public {
        vm.expectRevert(abi.encodeWithSelector(GaugeDoesNotExist.selector, _gauge));
        voter.activateGauge(_gauge);
    }

    // can reactivate an existing gauge
    function testFuzz_ActivateGaugeExists(address _gauge, string calldata metadata) public {
        vm.assume(_gauge != address(0));
        voter.createGauge(_gauge, metadata);
        voter.deactivateGauge(_gauge);
        vm.expectEmit(true, false, false, true);
        emit GaugeActivated(_gauge);
        voter.activateGauge(_gauge);

        assertEq(voter.getAllGauges().length, 1);
        assertEq(voter.isActive(_gauge), true);
    }

    // can't activate an already activated gauge
    function testFuzz_ActivateGaugeAlreadyActivated(
        address _gauge,
        string calldata metadata
    ) public {
        vm.assume(_gauge != address(0));
        voter.createGauge(_gauge, metadata);
        vm.expectRevert(GaugeActivationUnchanged.selector);
        voter.activateGauge(_gauge);
    }

    // can't update metadata on a non-existent gauge
    function testFuzz_UpdateGaugeMetadata(address _gauge, string calldata metadata) public {
        vm.expectRevert(abi.encodeWithSelector(GaugeDoesNotExist.selector, _gauge));
        voter.updateGaugeMetadata(_gauge, metadata);
    }

    function testCannotCreateZeroGauge() public {
        vm.expectRevert(ZeroGauge.selector);
        voter.createGauge(address(0), "");
    }

    // can update metadata on an existing gauge
    function testFuzz_UpdateGaugeMetadataExists(
        address _gauge,
        string calldata metadata,
        string calldata newMetadata
    ) public {
        vm.assume(_gauge != address(0));
        voter.createGauge(_gauge, metadata);
        vm.expectEmit(true, false, false, true);
        emit GaugeMetadataUpdated(_gauge, newMetadata);
        voter.updateGaugeMetadata(_gauge, newMetadata);
    }

    function testFuzz_canUpdateGaugeMetadata(address _gauge, string calldata metadata) public {
        vm.assume(_gauge != address(0));
        voter.createGauge(_gauge, metadata);

        assertEq(voter.getGauge(_gauge).metadataURI, metadata);

        string memory newMetadata = "new metadata";
        voter.updateGaugeMetadata(_gauge, newMetadata);

        assertEq(voter.getGauge(_gauge).metadataURI, newMetadata);
    }

    // can pause votes and resets
    function testCanPauseVoteAndResets() public {
        bytes memory err = "Pausable: paused";

        voter.pause();

        GaugeVote[] memory votes;
        uint256[] memory tokenIds;

        vm.expectRevert(err);
        voter.vote(0, votes);

        vm.expectRevert(err);
        voter.voteMultiple(tokenIds, votes);

        vm.expectRevert(err);
        voter.reset(0);
    }
}
