pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";

// aragon contracts
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig, MultisigSetup} from "@aragon/multisig/MultisigSetup.sol";

import {MockPluginSetupProcessor} from "@mocks/osx/MockPSP.sol";
import {MockDAOFactory} from "@mocks/osx/MockDAOFactory.sol";
import {MockERC20} from "@mocks/MockERC20.sol";

import "./helpers/OSxHelpers.sol";

import {IWithdrawalQueueErrors} from "src/escrow/increasing/interfaces/IVotingEscrowIncreasing.sol";
import {VotingEscrowSetup, VotingEscrow, QuadraticIncreasingEscrow, ExitQueue} from "src/escrow/increasing/VotingEscrowSetup.sol";
import {SimpleGaugeVoter, SimpleGaugeVoterSetup} from "src/voting/SimpleGaugeVoterSetup.sol";

/**
 * This is going to be a simple E2E test that will build the contracts on Aragon and run a deposit / withdraw flow.
 *
 * We need to:
 *
 * - Deploy the OSx framework
 * - Deploy a DAO
 * - Define our pluginSetup contract to deploy the VE
 * - Deploy the VE
 * - Do a deposit
 * - Check balance
 * - Do a vote
 * - Queue a withdraw
 * - Withdraw
 */
contract TestE2E is Test, IWithdrawalQueueErrors {
    MultisigSetup multisigSetup;
    VotingEscrowSetup veSetup;
    SimpleGaugeVoterSetup voterSetup;

    // permissions
    PermissionLib.MultiTargetPermission[] veSetupPermissions;
    PermissionLib.MultiTargetPermission[] voterSetupPermissions;

    MockPluginSetupProcessor psp;
    MockDAOFactory daoFactory;
    MockERC20 token;

    VotingEscrow ve;
    QuadraticIncreasingEscrow curve;
    SimpleGaugeVoter voter;
    ExitQueue queue;

    IDAO dao;
    Multisig multisig;

    address deployer = address(0x420);
    address user = address(0x69);

    uint256 constant COOLDOWN = 3 days;
    uint256 constant DEPOSIT = 1000 ether;

    uint tokenId;

    address gaugeTheFirst = address(0x1337);
    address gaugeTheSecond = address(0x7331);

    function testE2E() public {
        // clock reset
        vm.roll(0);
        vm.warp(0);

        // Deploy the OSx framework
        _deployOSX();
        // Deploy a DAO
        _deployDAOAndMSig();

        // new block for multisig
        vm.roll(1);
        // Define our pluginSetup contract to deploy the VE
        _setupVeContracts();
        _setupVoterContracts();

        // apply the installation (nothing needed just yet)
        _applyVeSetup();

        _addLabels();

        // main test
        _makeDeposit();
        _checkBalanceOverTime();

        // setup gauges
        _createGaugesActivateVoting();

        // vote
        _vote();
        _checkVoteEpoch();

        // withdraw
        _withdraw();
    }

    function _withdraw() internal {
        vm.startPrank(user);
        {
            vm.expectRevert(abi.encodeWithSelector(NotTicketHolder.selector));
            ve.withdraw(tokenId);

            // reset votes to clear
            voter.reset(tokenId);

            // enter the queue
            ve.beginWithdrawal(tokenId);
            assertEq(ve.balanceOf(user), 0, "User should have no tokens");
            assertEq(ve.balanceOf(address(ve)), 1, "VE should have the NFT");

            // wait for 1 day
            vm.warp(block.timestamp + 1 days);

            vm.expectRevert(abi.encodeWithSelector(CannotExit.selector));
            ve.withdraw(tokenId);

            // wait for the cooldown
            vm.warp(block.timestamp + COOLDOWN - 1 days);

            ve.withdraw(tokenId);
            assertEq(ve.balanceOf(user), 0, "User not should have the token");
            assertEq(ve.balanceOf(address(ve)), 0, "VE should not have the NFT");
            assertEq(token.balanceOf(user), DEPOSIT, "User should have the tokens");
        }
        vm.stopPrank();
    }

    function _checkVoteEpoch() internal {
        // warp to the distribution window
        vm.warp(block.timestamp + 1 weeks);
        assertEq(voter.votingActive(), false, "Voting should not be active");

        vm.warp(block.timestamp + 1 weeks);
        assertEq(voter.votingActive(), true, "Voting should be active again");
    }

    function _vote() internal {
        address[] memory targets = new address[](2);
        uint256[] memory weights = new uint256[](2);
        targets[0] = gaugeTheFirst;
        targets[1] = gaugeTheSecond;

        weights[0] = 25;
        weights[1] = 75;

        vm.startPrank(user);
        {
            voter.vote(tokenId, targets, weights);
        }
        vm.stopPrank();

        // check, should be 25% of 6*DEPOSIT in the first gauge
        // and 75% of 6*DEPOSIT in the second gauge
        uint expectedFirst = (6 * DEPOSIT) / 4;
        uint expectedSecond = (6 * DEPOSIT) - expectedFirst;

        assertEq(voter.weights(gaugeTheFirst), expectedFirst, "First gauge weight incorrect");
        assertEq(voter.weights(gaugeTheSecond), expectedSecond, "Second gauge weight incorrect");
    }

    function _createGaugesActivateVoting() internal {
        IDAO.Action[] memory actions = new IDAO.Action[](3);

        // action 0: create the first gauge
        actions[0] = IDAO.Action({
            to: address(voter),
            value: 0,
            data: abi.encodeWithSelector(voter.createGaugeWithMetadata.selector, gaugeTheFirst, "First Gauge")
        });

        // action 1: create the second gauge
        actions[1] = IDAO.Action({
            to: address(voter),
            value: 0,
            data: abi.encodeWithSelector(voter.createGaugeWithMetadata.selector, gaugeTheSecond, "Second Gauge")
        });

        // action 2: activate the voting
        actions[2] = IDAO.Action({
            to: address(voter),
            value: 0,
            data: abi.encodeWithSelector(voter.initializer.selector)
        });

        // create a proposal
        vm.startPrank(deployer);
        {
            multisig.createProposal({
                _metadata: "",
                _actions: actions,
                _allowFailureMap: 0,
                _approveProposal: true,
                _tryExecution: true,
                _startDate: 0,
                _endDate: uint64(block.timestamp + 1)
            });
        }
        vm.stopPrank();

        assertEq(voter.currentEpoch(), 0, "Epoch should be 0");
        assertEq(voter.votingActive(), false, "Voting should not be active");

        vm.warp(block.timestamp + 1 hours + 1);

        assertEq(voter.votingActive(), true, "Voting should be active");
    }

    function _makeDeposit() internal {
        // mint tokens
        token.mint(user, DEPOSIT);

        vm.startPrank(user);
        {
            token.approve(address(ve), DEPOSIT);
            tokenId = ve.createLock(DEPOSIT);

            // check the user owns the nft
            assertEq(tokenId, 1, "Token ID should be 1");
            assertEq(ve.balanceOf(user), 1, "User should have 1 token");
            assertEq(ve.ownerOf(tokenId), user, "User should own the token");
            assertEq(token.balanceOf(address(ve)), DEPOSIT, "VE should have the tokens");
            assertEq(token.balanceOf(user), 0, "User should have no tokens");
        }
        vm.stopPrank();
    }

    function _checkBalanceOverTime() internal {
        uint start = block.timestamp;
        // balance now is zero but Warm up
        assertEq(curve.votingPowerAt(tokenId, 0), 0, "Balance after deposit before warmup");
        assertEq(curve.isWarm(tokenId), false, "Not Warm up");

        // wait for warmup
        vm.warp(block.timestamp + curve.WARMUP_PERIOD());
        assertEq(curve.votingPowerAt(tokenId, 0), 0, "Balance after deposit before warmup");
        assertEq(curve.isWarm(tokenId), false, "Not Warm up");

        // warmup complete
        vm.warp(block.timestamp + 1);
        // python:     1067.784543380942094336
        // solmate:    1067.784483312193384992
        assertEq(
            curve.votingPowerAt(tokenId, block.timestamp),
            1067784483312193384992,
            "Balance incorrect after warmup"
        );
        assertEq(curve.isWarm(tokenId), true, "Still warming up");

        // warp to the start of period 2
        vm.warp(start + curve.period());
        // python:     1428.571428571428683776
        // solmate:    1428.570120419660799763
        assertEq(curve.votingPowerAt(tokenId, block.timestamp), 1428570120419660799763, "Balance incorrect after p1");

        // warp to the final period
        // TECHNICALLY, this should finish at exactly 5 periods but
        // 30 seconds off is okay
        vm.warp(start + curve.period() * 5 + 30);
        assertEq(curve.votingPowerAt(tokenId, block.timestamp), 6 * DEPOSIT, "Balance incorrect after p6");
    }

    function _deployOSX() internal {
        // deploy the mock PSP with the multisig  plugin
        multisigSetup = new MultisigSetup();
        psp = new MockPluginSetupProcessor(address(multisigSetup));
        daoFactory = new MockDAOFactory(psp);
    }

    function _deployDAOAndMSig() internal {
        // use the OSx DAO factory with the Plugin
        address[] memory members = new address[](1);
        members[0] = deployer;

        // encode a 1/1 multisig that can be adjusted later
        bytes memory data = abi.encode(members, Multisig.MultisigSettings({onlyListed: true, minApprovals: 1}));

        dao = daoFactory.createDao(_mockDAOSettings(), _mockPluginSettings(data));

        // nonce 0 is something?
        // nonce 1 is implementation contract
        // nonce 2 is the msig contract behind the proxy
        multisig = Multisig(computeAddress(address(multisigSetup), 2));
    }

    function _setupVeContracts() public {
        token = new MockERC20();

        // deploy setup
        veSetup = new VotingEscrowSetup();

        // push to the PSP
        psp.queueSetup(address(veSetup));

        // prepare the installation
        bytes memory data = abi.encode(address(token), COOLDOWN, "Voting Escrow NFT", "veNFT");
        (address vePluginAddress, IPluginSetup.PreparedSetupData memory vePluginPreparedSetupData) = psp
            .prepareInstallation(address(dao), _mockPrepareInstallationParams(data));

        // fetch the contracts
        ve = VotingEscrow(vePluginAddress);
        address[] memory helpers = vePluginPreparedSetupData.helpers;
        curve = QuadraticIncreasingEscrow(helpers[0]);
        queue = ExitQueue(helpers[1]);

        // set the permissions
        for (uint i = 0; i < vePluginPreparedSetupData.permissions.length; i++) {
            veSetupPermissions.push(vePluginPreparedSetupData.permissions[i]);
        }
    }

    function _setupVoterContracts() public {
        // deploy setup
        voterSetup = new SimpleGaugeVoterSetup();

        // push to the PSP
        psp.queueSetup(address(voterSetup));

        // prepare the installation
        bytes memory data = abi.encode(address(ve), false);
        (address voterPluginAddress, IPluginSetup.PreparedSetupData memory voterPluginPreparedSetupData) = psp
            .prepareInstallation(address(dao), _mockPrepareInstallationParams(data));

        // fetch the contracts
        voter = SimpleGaugeVoter(voterPluginAddress);

        // set the permissions
        for (uint i = 0; i < voterPluginPreparedSetupData.permissions.length; i++) {
            veSetupPermissions.push(voterPluginPreparedSetupData.permissions[i]);
        }
    }

    function _actions() internal view returns (IDAO.Action[] memory) {
        IDAO.Action[] memory actions = new IDAO.Action[](5);

        // action 0: apply the ve installation
        actions[0] = IDAO.Action({
            to: address(psp),
            value: 0,
            data: abi.encodeCall(
                psp.applyInstallation,
                (address(dao), _mockApplyInstallationParams(address(ve), veSetupPermissions))
            )
        });

        // action 1: apply the voter installation
        actions[1] = IDAO.Action({
            to: address(psp),
            value: 0,
            data: abi.encodeCall(
                psp.applyInstallation,
                (address(dao), _mockApplyInstallationParams(address(voter), voterSetupPermissions))
            )
        });

        // action 2: activate the curve on the ve
        actions[2] = IDAO.Action({
            to: address(ve),
            value: 0,
            data: abi.encodeWithSelector(ve.setCurve.selector, address(curve))
        });

        // action 3: activate the queue on the ve
        actions[3] = IDAO.Action({
            to: address(ve),
            value: 0,
            data: abi.encodeWithSelector(ve.setQueue.selector, address(queue))
        });

        // action 4: set the voter
        actions[4] = IDAO.Action({
            to: address(ve),
            value: 0,
            data: abi.encodeWithSelector(ve.setVoter.selector, address(voter))
        });

        return wrapGrantRevokeRoot(DAO(payable(address(dao))), address(psp), actions);
    }

    function _applyVeSetup() internal {
        // todo - nothing for now
        IDAO.Action[] memory actions = _actions();

        // execute the actions
        vm.startPrank(deployer);
        {
            multisig.createProposal({
                _metadata: "",
                _actions: actions,
                _allowFailureMap: 0,
                _approveProposal: true,
                _tryExecution: true,
                _startDate: 0,
                _endDate: uint64(block.timestamp + 1)
            });
        }
        vm.stopPrank();
    }

    function _addLabels() internal {
        vm.label(gaugeTheFirst, "gaugeTheFirst");
        vm.label(gaugeTheSecond, "gaugeTheSecond");
        vm.label(deployer, "deployer");
        vm.label(user, "user");
    }
}