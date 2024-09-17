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

import "./helpers/OSxHelpers.sol";

import {Clock} from "@clock/Clock.sol";
import {IEscrowCurveUserStorage} from "@escrow-interfaces/IEscrowCurveIncreasing.sol";
import {IWithdrawalQueueErrors} from "src/escrow/increasing/interfaces/IVotingEscrow.sol";
import {IGaugeVote} from "src/voting/ISimpleGaugeVoter.sol";
import {VotingEscrow, Lock, QuadraticIncreasingEscrow, ExitQueue, SimpleGaugeVoter, SimpleGaugeVoterSetup, ISimpleGaugeVoterSetupParams} from "src/voting/SimpleGaugeVoterSetup.sol";

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
contract TestE2E is Test, IWithdrawalQueueErrors, IGaugeVote, IEscrowCurveUserStorage {
    MultisigSetup multisigSetup;
    SimpleGaugeVoterSetup voterSetup;

    // permissions
    PermissionLib.MultiTargetPermission[] voterSetupPermissions;

    MockPluginSetupProcessor psp;
    MockDAOFactory daoFactory;
    MockERC20 token;

    VotingEscrow ve;
    Lock nftLock;
    QuadraticIncreasingEscrow curve;
    SimpleGaugeVoter voter;
    ExitQueue queue;
    Clock clock;

    IDAO dao;
    Multisig multisig;

    address deployer = address(0x420);
    address user = address(0x69);

    uint256 constant COOLDOWN = 3 days;
    uint256 constant DEPOSIT = 1000 ether;

    uint tokenId;
    uint NUM_PERIODS = 5;

    address gaugeTheFirst = address(0x1337);
    address gaugeTheSecond = address(0x7331);

    uint depositTime;

    error MinLockNotReached(uint256 minLock, uint256 expected, uint256 actual);

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
        _setupVoterContracts();

        // apply the installation (nothing needed just yet)
        _applySetup();

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
            uint atm = block.timestamp;

            vm.expectRevert(NotTicketHolder.selector);
            ve.withdraw(tokenId);

            // reset votes to clear
            voter.reset(tokenId);

            // approve the withdrawal
            nftLock.approve(address(ve), tokenId);

            // can't queue because the min lock is not reached
            uint256 minLock = queue.timeToMinLock(tokenId);
            uint256 expectedTime = 20 weeks - depositTime;
            assertEq(minLock, expectedTime, "Min lock time incorrect");

            bytes memory err = abi.encodeWithSelector(
                MinLockNotReached.selector,
                1,
                queue.minLock(),
                expectedTime
            );
            // expect revert
            vm.expectRevert(err);
            ve.beginWithdrawal(tokenId);

            // warp to the min lock + start - expect success
            vm.warp(atm + expectedTime);
            ve.beginWithdrawal(tokenId);

            // enter the queue
            assertEq(nftLock.balanceOf(user), 0, "User should have no tokens");
            assertEq(nftLock.balanceOf(address(ve)), 1, "VE should have the NFT");

            // readjust the cached time
            atm = block.timestamp;

            // wait for 1 day
            vm.warp(atm + 1 days);

            vm.expectRevert(CannotExit.selector);
            ve.withdraw(tokenId);

            // the cooldown is not enough: we snap to the end of the voting period

            // wait for the cooldown
            vm.warp(atm + COOLDOWN);

            vm.expectRevert(CannotExit.selector);
            ve.withdraw(tokenId);

            // warp to the end of the voting period
            vm.warp(atm + 1 weeks);
            ve.withdraw(tokenId);

            assertEq(nftLock.balanceOf(user), 0, "User not should have the token");
            assertEq(nftLock.balanceOf(address(ve)), 0, "VE should not have the NFT");
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
        GaugeVote[] memory votes = new GaugeVote[](2);
        votes[0] = GaugeVote({gauge: gaugeTheFirst, weight: 25});
        votes[1] = GaugeVote({gauge: gaugeTheSecond, weight: 75});

        vm.startPrank(user);
        {
            voter.vote(tokenId, votes);
        }
        vm.stopPrank();

        uint maxDeposit = curve.previewMaxBias(DEPOSIT);

        // check, should be 25% of 6*DEPOSIT in the first gauge
        // and 75% of 6*DEPOSIT in the second gauge
        uint expectedFirst = maxDeposit / 4;
        uint expectedSecond = maxDeposit - expectedFirst;

        assertEq(voter.gaugeVotes(gaugeTheFirst), expectedFirst, "First gauge weight incorrect");
        assertEq(voter.gaugeVotes(gaugeTheSecond), expectedSecond, "Second gauge weight incorrect");
    }

    function _createGaugesActivateVoting() internal {
        IDAO.Action[] memory actions = new IDAO.Action[](3);

        // action 0: create the first gauge
        actions[0] = IDAO.Action({
            to: address(voter),
            value: 0,
            data: abi.encodeWithSelector(voter.createGauge.selector, gaugeTheFirst, "First Gauge")
        });

        // action 1: create the second gauge
        actions[1] = IDAO.Action({
            to: address(voter),
            value: 0,
            data: abi.encodeWithSelector(voter.createGauge.selector, gaugeTheSecond, "Second Gauge")
        });

        // action 2: activate the voting
        actions[2] = IDAO.Action({
            to: address(voter),
            value: 0,
            data: abi.encodeWithSelector(voter.unpause.selector)
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

            // warp to exactly the next epoch so that warmup math is easier
            uint expectedStart = clock.epochNextCheckpointTs();
            vm.warp(expectedStart);

            // create the lock
            tokenId = ve.createLock(DEPOSIT);

            // fetch the starttime of the lock
            depositTime = ve.locked(tokenId).start;
            assertEq(depositTime, expectedStart, "Deposit time incorrect");

            // check the user owns the nft
            assertEq(tokenId, 1, "Token ID should be 1");
            assertEq(nftLock.balanceOf(user), 1, "User should have 1 token");
            assertEq(nftLock.ownerOf(tokenId), user, "User should own the token");
            assertEq(token.balanceOf(address(ve)), DEPOSIT, "VE should have the tokens");
            assertEq(token.balanceOf(user), 0, "User should have no tokens");
        }
        vm.stopPrank();
    }

    function _checkBalanceOverTime() internal {
        uint start = block.timestamp;
        // balance now is zero but Warm up
        assertEq(curve.votingPowerAt(tokenId, 0), 0, "Balance after deposit before warmup");
        assertEq(curve.isWarm(tokenId), false, "Should not be warm after 0 seconds");

        // wait for warmup
        vm.warp(block.timestamp + curve.warmupPeriod() - 1);
        assertEq(curve.votingPowerAt(tokenId, 0), 0, "Balance after deposit before warmup");
        assertEq(curve.isWarm(tokenId), false, "Should not be warm yet");

        // warmup complete
        vm.warp(block.timestamp + 1);
        // python:    1067.784256559766831104
        // solmate:   1067.784196491481599990
        assertEq(
            curve.votingPowerAt(tokenId, block.timestamp),
            1067784196491481599990,
            "Balance incorrect after warmup"
        );
        assertEq(curve.isWarm(tokenId), true, "Still warming up");

        // warp to the start of period 2
        vm.warp(start + clock.epochDuration());
        // python:     1428.571428571428683776
        // solmate:    1428.570120419660799763
        assertEq(
            curve.votingPowerAt(tokenId, block.timestamp),
            1428570120419660799763,
            "Balance incorrect after p1"
        );

        // warp to the final period
        // TECHNICALLY, this should finish at exactly 5 periods but
        // 30 seconds off is okay
        vm.warp(start + clock.epochDuration() * 5 + 30);
        assertEq(
            curve.votingPowerAt(tokenId, block.timestamp),
            5999967296216703996928,
            "Balance incorrect after p6"
        );
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
        bytes memory data = abi.encode(
            members,
            Multisig.MultisigSettings({onlyListed: true, minApprovals: 1})
        );

        dao = daoFactory.createDao(_mockDAOSettings(), _mockPluginSettings(data));

        // nonce 0 is something?
        // nonce 1 is implementation contract
        // nonce 2 is the msig contract behind the proxy
        multisig = Multisig(computeAddress(address(multisigSetup), 2));
    }

    function _setupVoterContracts() public {
        token = new MockERC20();

        // deploy setup
        voterSetup = new SimpleGaugeVoterSetup(
            address(new SimpleGaugeVoter()),
            address(new QuadraticIncreasingEscrow()),
            address(new ExitQueue()),
            address(new VotingEscrow()),
            address(new Clock()),
            address(new Lock())
        );

        // push to the PSP
        psp.queueSetup(address(voterSetup));

        // prepare the installation
        bytes memory data = abi.encode(
            ISimpleGaugeVoterSetupParams({
                isPaused: true,
                token: address(token),
                veTokenName: "VE Token",
                veTokenSymbol: "VE",
                warmup: 3 days,
                cooldown: 3 days,
                feePercent: 0,
                minLock: 20 weeks
            })
        );
        (address pluginAddress, IPluginSetup.PreparedSetupData memory preparedSetupData) = psp
            .prepareInstallation(address(dao), _mockPrepareInstallationParams(data));

        // fetch the contracts
        voter = SimpleGaugeVoter(pluginAddress);
        address[] memory helpers = preparedSetupData.helpers;
        curve = QuadraticIncreasingEscrow(helpers[0]);
        queue = ExitQueue(helpers[1]);
        ve = VotingEscrow(helpers[2]);
        clock = Clock(helpers[3]);
        nftLock = Lock(helpers[4]);

        // set the permissions
        for (uint i = 0; i < preparedSetupData.permissions.length; i++) {
            voterSetupPermissions.push(preparedSetupData.permissions[i]);
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
                (address(dao), _mockApplyInstallationParams(address(ve), voterSetupPermissions))
            )
        });

        // action 2: activate the curve on the ve
        actions[1] = IDAO.Action({
            to: address(ve),
            value: 0,
            data: abi.encodeWithSelector(ve.setCurve.selector, address(curve))
        });

        // action 3: activate the queue on the ve
        actions[2] = IDAO.Action({
            to: address(ve),
            value: 0,
            data: abi.encodeWithSelector(ve.setQueue.selector, address(queue))
        });

        // action 4: set the voter
        actions[3] = IDAO.Action({
            to: address(ve),
            value: 0,
            data: abi.encodeWithSelector(ve.setVoter.selector, address(voter))
        });

        actions[4] = IDAO.Action({
            to: address(ve),
            value: 0,
            data: abi.encodeWithSelector(ve.setLockNFT.selector, address(nftLock))
        });

        return wrapGrantRevokeRoot(DAO(payable(address(dao))), address(psp), actions);
    }

    function _applySetup() internal {
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
