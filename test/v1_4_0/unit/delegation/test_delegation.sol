// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {MockERC20} from "@solmate/test/utils/mocks/MockERC20.sol";
import {MockPluginSetupProcessor} from "@mocks/osx/MockPSP.sol";
import {MockPluginSetupProcessorMulti} from "@mocks/osx/MockPSPMulti.sol";
import {MockPluginRepoRegistry} from "@mocks/osx/MockPluginRepoRegistry.sol";
import {MockDAOFactory} from "@mocks/osx/MockDAOFactory.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginRepoRegistry} from "@aragon/osx/framework/plugin/repo/PluginRepoRegistry.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {Addresslist} from "@aragon/osx/plugins/utils/Addresslist.sol";
import {MultisigSetup as MultisigPluginSetup} from "@aragon/osx/plugins/governance/multisig/MultisigSetup.sol";

import {IGlobalPoint, DynamicDelegator} from "@delegation/DynamicDelegator.sol";
import {SimpleGaugeVoterSetup, VotingEscrow, Clock, GaugePluginSet, Lock, QuadraticIncreasingEscrow as LinearEscrow, ExitQueue, SimpleGaugeVoter, GaugesDaoFactory, Deployment, DeploymentParameters, TokenParameters} from "../../versions.sol";

contract DelegationTest is Test {
    GaugesDaoFactory factory;
    DAO dao;
    VotingEscrow escrow;
    Clock clock;
    Lock lock;
    LinearEscrow curve;
    MockERC20 token;

    address jordan = address(1234);
    address giorgi = address(6543);
    function setUp() public {
        _factoryDeploy();
    }

    function testDelegate() public {
        Deployment memory deployment = factory.getDeployment();

        GaugePluginSet memory ps = deployment.gaugeVoterPluginSets[0];
        dao = DAO(deployment.dao);
        escrow = VotingEscrow(ps.votingEscrow);
        clock = Clock(ps.clock);
        lock = Lock(ps.nftLock);
        curve = LinearEscrow(ps.curve);
        token = MockERC20(escrow.token());

        DynamicDelegator delegator = new DynamicDelegator();
        delegator.initialize(address(escrow), address(dao), address(clock));

        // create a lock
        token.mint(address(this), 1000);
        token.approve(address(escrow), 1000);
        escrow.createLockFor(1000, jordan);

        // delegate
        vm.startPrank(jordan);
        {
            delegator.setAutoDelegation(true);
            delegator.delegate(giorgi);
        }
        vm.stopPrank();

        // check delegation

        // assertEq(escrow.delegates(address(this)), 1000);
    }

    function _factoryDeploy() internal {
        address[] memory multisigMembers = new address[](13);
        for (uint256 i = 0; i < 13; i++) {
            multisigMembers[i] = address(uint160(i + 5));
        }

        PluginRepoFactory pRefoFactory = new PluginRepoFactory(
            PluginRepoRegistry(address(new MockPluginRepoRegistry()))
        );

        // Publish repo
        MultisigPluginSetup multisigPluginSetup = new MultisigPluginSetup();
        PluginRepo multisigPluginRepo = PluginRepoFactory(pRefoFactory)
            .createPluginRepoWithFirstVersion(
                "multisig-subdomain",
                address(multisigPluginSetup),
                address(this),
                " ",
                " "
            );

        SimpleGaugeVoterSetup gaugeVoterPluginSetup = new SimpleGaugeVoterSetup(
            address(new SimpleGaugeVoter()),
            address(new LinearEscrow()),
            address(new ExitQueue()),
            address(new VotingEscrow()),
            address(new Clock()),
            address(new Lock())
        );

        TokenParameters[] memory tokenParameters = new TokenParameters[](2);
        tokenParameters[0] = TokenParameters({
            token: address(new MockERC20("T1", "T1", 18)),
            veTokenName: "Name 1",
            veTokenSymbol: "TK1"
        });
        tokenParameters[1] = TokenParameters({
            token: address(new MockERC20("T2", "T2", 18)),
            veTokenName: "Name 2",
            veTokenSymbol: "TK2"
        });

        // PSP with voter plugin setup and multisig
        MockPluginSetupProcessorMulti psp;
        {
            address[] memory pluginSetups = new address[](3);
            pluginSetups[0] = address(gaugeVoterPluginSetup); // Token 1
            pluginSetups[1] = address(gaugeVoterPluginSetup); // Token 2
            pluginSetups[2] = address(multisigPluginSetup);

            psp = new MockPluginSetupProcessorMulti(pluginSetups);
        }
        MockDAOFactory daoFactory = new MockDAOFactory(MockPluginSetupProcessor(address(psp)));

        DeploymentParameters memory creationParams = DeploymentParameters({
            // Multisig settings
            minApprovals: 2,
            multisigMembers: multisigMembers,
            // Gauge Voter
            tokenParameters: tokenParameters,
            feePercent: 500,
            warmupPeriod: 0,
            cooldownPeriod: 2345,
            minLockDuration: 3456,
            minDeposit: 1,
            votingPaused: false,
            // Standard multisig repo
            multisigPluginRepo: multisigPluginRepo,
            multisigPluginRelease: 1,
            multisigPluginBuild: 2,
            // Voter plugin setup and ENS
            voterPluginSetup: gaugeVoterPluginSetup,
            voterEnsSubdomain: "gauge-ens-subdomain",
            // OSx addresses
            osxDaoFactory: address(daoFactory),
            pluginSetupProcessor: PluginSetupProcessor(address(psp)),
            pluginRepoFactory: pRefoFactory
        });

        factory = new GaugesDaoFactory(creationParams);

        factory.deployOnce();

        vm.roll(block.number + 1); // mint one block
    }
}
