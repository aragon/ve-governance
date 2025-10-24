/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

// aragon contracts
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";

import {MockERC20} from "@mocks/MockERC20.sol";

import "@helpers/OSxHelpers.sol";
import {ProxyLib} from "@libs/ProxyLib.sol";
import {CurveConstantLib} from "@libs/CurveConstantLib.sol";

import {PluginRepoFactory} from "@aragon/osx/framework/plugin/repo/PluginRepoFactory.sol";
import {PluginSetupProcessor} from "@aragon/osx/framework/plugin/setup/PluginSetupProcessor.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";

import {
    Lock,
    Clock,
    VotingEscrow,
    Curve as LinearIncreasingCurve,
    ExitQueue,
    SimpleGaugeVoter,
    SimpleGaugeVoterSetup,
    EscrowIVotesAdapter,
    GaugesDaoFactory,
    DeploymentParameters,
    Deployment,
    TokenParameters,
    GaugeVoterSetup,
    Curve
} from "../versions.sol";

import {FixedPointBase} from "./FixedPointBase.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {
    ProtocolFactoryBuilder
} from "@aragon/protocol-factory/test/helpers/ProtocolFactoryBuilder.sol";
import {ProtocolFactory} from "@aragon/protocol-factory/src/ProtocolFactory.sol";
import {CurveConstantLib} from "@libs/CurveConstantLib.sol";

contract FactoryBase is StdInvariant, Test, FixedPointBase {
    SimpleGaugeVoter internal voter;
    Curve internal curve;
    ExitQueue internal queue;
    VotingEscrow internal escrow;
    Clock internal clock;
    Lock internal nftLock;
    EscrowIVotesAdapter internal ivotesAdapter;
    DAO internal dao;

    function setUp() public virtual {
        ProtocolFactory.Deployment memory protocolDeployment;

        ProtocolFactoryBuilder builder = new ProtocolFactoryBuilder();
        ProtocolFactory protocolFactory = builder
            .withMultisigPlugin(1, 3, "releaseMeta", "buildMeta", "multisig-1")
            .build();
        protocolFactory.deployOnce();
        protocolDeployment = protocolFactory.getDeployment();
        
        address[] memory members = new address[](1);
        members[0] = address(this);

        TokenParameters[] memory tokenParameters = new TokenParameters[](1);
        tokenParameters[0] = TokenParameters({
            token: createTestToken(members),
            veTokenName: "VE Token 1",
            veTokenSymbol: "veTK1"
        });

        DeploymentParameters memory parameters = DeploymentParameters({
            daoSubdomain: "",
            daoMetadataURI: "",
            daoExecutor: address(0),
            // Multisig settings
            minApprovals: 1,
            multisigMembers: members,
            multisigMetadata: bytes("some-metadata"),
            // Gauge Voter
            tokenParameters: tokenParameters,
            feePercent: 1,
            cooldownPeriod: 1,
            minLockDuration: 2 days,
            votingPaused: false,
            minDeposit: 100,
            multisigPluginRepo: PluginRepo(protocolDeployment.multisigPluginRepo),
            multisigPluginRelease: 1,
            multisigPluginBuild: 3,
            voterPluginSetup: deployGaugeVoterPluginSetup(),
            voterEnsSubdomain: "some-string",
            osxDaoFactory: protocolDeployment.daoFactory,
            pluginSetupProcessor: PluginSetupProcessor(protocolDeployment.pluginSetupProcessor),
            pluginRepoFactory: PluginRepoFactory(protocolDeployment.pluginRepoFactory)
        });

        GaugesDaoFactory factory = new GaugesDaoFactory(parameters);
        factory.deployOnce();
        Deployment memory deployment = factory.getDeployment();

        voter = deployment.gaugeVoterPluginSets[0].plugin;
        curve = deployment.gaugeVoterPluginSets[0].curve;
        queue = deployment.gaugeVoterPluginSets[0].exitQueue;
        escrow = deployment.gaugeVoterPluginSets[0].votingEscrow;
        clock = deployment.gaugeVoterPluginSets[0].clock;
        nftLock = deployment.gaugeVoterPluginSets[0].nftLock;
        ivotesAdapter = deployment.gaugeVoterPluginSets[0].delegationAdapter;
        dao = deployment.dao;

        vm.startPrank(address(deployment.dao));
        escrow.enableSplit();
        nftLock.enableTransfers();
        deployment.dao.grant(
            address(ivotesAdapter),
            address(type(uint160).max),
            ivotesAdapter.DELEGATION_TOKEN_ROLE()
        );
        vm.stopPrank();

        FixedPointBase.initialize(curve.maxTime(), clock.checkpointInterval());
    }

    function createTestToken(address[] memory holders) internal returns (address) {
        MockERC20 newToken = new MockERC20();

        for (uint256 i = 0; i < holders.length; i++) {
            newToken.mint(holders[i], 5000 ether);
        }

        return address(newToken);
    }

    function deployGaugeVoterPluginSetup() internal returns (GaugeVoterSetup result) {
        (int256[3] memory coefficients, uint256 maxEpoch) = CurveConstantLib.getCoefficients();

        result = new GaugeVoterSetup(
            address(new SimpleGaugeVoter()),
            address(new Curve(coefficients, maxEpoch)),
            address(new ExitQueue()),
            address(new VotingEscrow()),
            address(new Clock()),
            address(new Lock()),
            address(new EscrowIVotesAdapter(coefficients, maxEpoch))
        );
    }
}
