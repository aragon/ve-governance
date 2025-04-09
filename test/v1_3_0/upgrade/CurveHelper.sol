pragma solidity ^0.8.17;

import {SimpleGaugeVoterSetup, IGaugeVote, IEscrowCurveIncreasing, VotingEscrow, Clock, Lock, QuadraticIncreasingEscrow, ExitQueue, SimpleGaugeVoter, GaugesDaoFactory as GaugesDaoFactoryV1_0_0, Deployment, DeploymentParameters, TokenParameters, GaugePluginSet} from "test/v1_0_0/versions.sol";

struct CachedViewArguments {
    uint256 tokenId;
    uint256 timestamp;
    uint256 amount;
    uint256 tokenInterval;
}

struct CachedView {
    address escrow;
    address clock;
    uint48 warmupPeriod;
    uint256 tokenPointInterval;
    uint256 maxBias;
    bool isWarm;
    IEscrowCurveIncreasing.TokenPoint tokenPointHistory;
    int256[3] coefficientsPlain;
    uint256 bias;
    uint256 votingPower;
}

function fetchState(
    QuadraticIncreasingEscrow target,
    CachedViewArguments memory args
) view returns (CachedView memory state) {
    state.escrow = target.escrow();
    state.clock = target.clock();
    state.warmupPeriod = target.warmupPeriod();

    state.tokenPointInterval = target.tokenPointIntervals(args.tokenId);
    state.tokenPointHistory = target.tokenPointHistory(args.tokenId, args.tokenInterval);

    state.coefficientsPlain = target.getCoefficients(args.amount);
    state.bias = target.getBias(args.timestamp, args.amount);
    state.maxBias = target.previewMaxBias(args.amount);

    state.isWarm = target.isWarm(args.tokenId);
    state.votingPower = target.votingPowerAt(args.tokenId, args.timestamp);
}
