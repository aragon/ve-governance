pragma solidity ^0.8.17;

import {
    SimpleGaugeVoterSetup,
    IGaugeVote,
    IEscrowCurveIncreasing,
    VotingEscrow,
    Clock,
    Lock,
    QuadraticIncreasingEscrow,
    ExitQueue,
    SimpleGaugeVoter,
    GaugesDaoFactory as GaugesDaoFactoryV1_0_0,
    Deployment,
    DeploymentParameters,
    TokenParameters,
    GaugePluginSet
} from "test/v1_0_0/versions.sol";

struct CachedViewArgumentsCurve {
    uint256 tokenId;
    uint256 timestamp;
    uint256 amount;
    uint256 tokenInterval;
    uint256 maturity;
    uint256 sampleTime;
}

struct CachedViewCurve {
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
    uint256 votingPowerSample;
    uint256 votingPowerMaturity;
}

function fetchStateCurve(
    QuadraticIncreasingEscrow target,
    CachedViewArgumentsCurve memory args
) view returns (CachedViewCurve memory state) {
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
    state.votingPowerSample = target.votingPowerAt(args.tokenId, args.sampleTime);
    state.votingPowerMaturity = target.votingPowerAt(args.tokenId, args.maturity);
}
