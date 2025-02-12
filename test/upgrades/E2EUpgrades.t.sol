// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {AragonTest} from "../base/AragonTest.sol";
import {console2 as console} from "forge-std/console2.sol";

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO, createTestDAO} from "@mocks/MockDAO.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Multisig, MultisigSetup} from "@aragon/multisig/MultisigSetup.sol";
import {UUPSUpgradeable as UUPS} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {MockERC20} from "@mocks/MockERC20.sol";

import "../helpers/OSxHelpers.sol";

import {
    GaugesDaoFactory as GaugesDaoFactory_v101,
    GaugePluginSet as GaugePluginSet_v101,
    Deployment as Deployment_v101
} from "@aragon/ve-governance-v101/factory/GaugesDaoFactory.sol";
import {
    DeployGauges as DeployGauges_v101,
    DeploymentParameters as DeploymentParameters_v101
} from "../../lib/ve-governance/v101/script/DeployGauges.s.sol";

import {
    Clock as Clock_v101,
    VotingEscrow as VotingEscrow_v101,
    Lock as Lock_v101,
    QuadraticIncreasingEscrow as QuadraticIncreasingEscrow_v101,
    ExitQueue as ExitQueue_v101,
    SimpleGaugeVoter as SimpleGaugeVoter_v101,
    SimpleGaugeVoterSetup as SimpleGaugeVoterSetup_v101,
    ISimpleGaugeVoterSetupParams as ISimpleGaugeVoterSetupParams_v101
} from '@aragon/ve-governance-v101/voting/SimpleGaugeVoterSetup.sol';

import {
    Clock as Clock_v110,
    VotingEscrow as VotingEscrow_v110,
    Lock as Lock_v110,
    QuadraticIncreasingEscrow as QuadraticIncreasingEscrow_v110,
    ExitQueue as ExitQueue_v110,
    SimpleGaugeVoter as SimpleGaugeVoter_v110,
    SimpleGaugeVoterSetup as SimpleGaugeVoterSetup_v110,
    ISimpleGaugeVoterSetupParams as ISimpleGaugeVoterSetupParams_v110
 } from "src/voting/SimpleGaugeVoterSetup.sol";


import {Upgrades} from "openzeppelin-foundry-upgrades/LegacyUpgrades.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {ProxyLib} from "@libs/ProxyLib.sol";


contract E2EUpgrades is AragonTest {
    using Address for address;
    using Clones for address;
    using ERC165Checker for address;
    using ProxyLib for address;

    GaugesDaoFactory_v101 factory;
    SimpleGaugeVoter_v101 voter;
    QuadraticIncreasingEscrow_v101 curve;
    ExitQueue_v101 queue;
    VotingEscrow_v101 escrow;
    Clock_v101 clock;
    Lock_v101 lock;

    DAO dao;

    MockERC20 token;

    function setUp() public {
        token = new MockERC20();
        dao = createTestDAO(address(this));

        address voterBase = address(new SimpleGaugeVoter_v101());
        address curveBase = address(new QuadraticIncreasingEscrow_v101());
        address queueBase = address(new ExitQueue_v101());
        address escrowBase = address(new VotingEscrow_v101());
        address clockBase = address(new Clock_v101());
        address lockBase = address(new Lock_v101());
        
        // deploy the clock
        clock = Clock_v101(
            clockBase.deployUUPSProxy(abi.encodeWithSelector(Clock_v101.initialize.selector, dao))
        );

        DAO(payable(address(dao))).grant({
            _who: address(this),
            _where: address(clock),
            _permissionId: clock.CLOCK_ADMIN_ROLE()
        });

        // deploy the escrow locker
        escrow = VotingEscrow_v101(
            escrowBase.deployUUPSProxy(
                abi.encodeCall(
                    VotingEscrow_v101.initialize,
                    (address(token), address(dao), address(clock), 0x0)
                )
            )
        );

        DAO(payable(address(dao))).grant({
            _who: address(this),
            _where: address(escrow),
            _permissionId: escrow.ESCROW_ADMIN_ROLE()
        });

        // deploy the voting contract (plugin)
        voter = SimpleGaugeVoter_v101(
            voterBase.deployUUPSProxy(
                abi.encodeCall(
                    SimpleGaugeVoter_v101.initialize,
                    (address(dao), address(escrow), true, address(clock))
                )
            )
        );

        DAO(payable(address(dao))).grant({
            _who: address(this),
            _where: address(voter),
            _permissionId: voter.GAUGE_ADMIN_ROLE()
        });

        // deploy the curve
        curve = QuadraticIncreasingEscrow_v101(
            curveBase.deployUUPSProxy(
                abi.encodeCall(
                    QuadraticIncreasingEscrow_v101.initialize,
                    (address(escrow), address(dao), 0, address(clock))
                )
            )
        );

        DAO(payable(address(dao))).grant({
            _who: address(this),
            _where: address(curve),
            _permissionId: curve.CURVE_ADMIN_ROLE()
        });

        // deploy the exit queue
        queue = ExitQueue_v101(
            queueBase.deployUUPSProxy(
                abi.encodeCall(
                    ExitQueue_v101.initialize,
                    (address(escrow), 0, address(dao), 0, address(clock), 1)
                )
            )
        );

        DAO(payable(address(dao))).grant({
            _who: address(this),
            _where: address(queue),
            _permissionId: queue.QUEUE_ADMIN_ROLE()
        });

        // deploy the escrow NFT
        lock = Lock_v101(
            lockBase.deployUUPSProxy(
                abi.encodeCall(
                    Lock_v101.initialize,
                    (address(escrow), "Test", "tt", address(dao))
                )
            )
        );

        DAO(payable(address(dao))).grant({
            _who: address(this),
            _where: address(lock),
            _permissionId: lock.LOCK_ADMIN_ROLE()
        });

        // increment the block by 1 to ensure we have a new block
        // A new multisig requires this after changing settings

        vm.roll(block.number + 1);
    }

    function testSimulateUpgrades() public {
        Options memory options;
        options.referenceBuildInfoDir = "ref_builds/build-info-v101";

        options.referenceContract = "build-info-v101:Lock";
        Upgrades.upgradeProxy(address(lock), "Lock.sol", "", options);

        options.referenceContract = "build-info-v101:VotingEscrow";
        Upgrades.upgradeProxy(address(escrow), "VotingEscrow.sol", "", options);

        options.referenceContract = "build-info-v101:SimpleGaugeVoter";
        Upgrades.upgradeProxy(address(voter), "SimpleGaugeVoter.sol", "", options);

        options.referenceContract = "build-info-v101:QuadraticIncreasingEscrow";
        Upgrades.upgradeProxy(address(curve), "QuadraticIncreasingEscrow.sol", "", options);

        options.referenceContract = "build-info-v101:ExitQueue";
        Upgrades.upgradeProxy(address(queue), "ExitQueue.sol", "", options);

        options.referenceContract = "build-info-v101:Clock";
        Upgrades.upgradeProxy(address(clock), "Clock.sol", "", options);
    }
}
