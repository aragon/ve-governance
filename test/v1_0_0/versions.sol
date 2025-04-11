pragma solidity ^0.8.17;

// imports file allows for copying test suite independently for different modules of ve
// import files here in your tests instead of from src

// contracts
import {
    Curve,
    // legacy
    Curve as QuadraticIncreasingEscrow,
    Clock,
    Lock,
    ExitQueue,
    VotingEscrow,
    GaugeVoter,
    GaugeVoterSetup
} from "@setup/GaugeVoterSetup.sol";
import {
    GaugesDaoFactory,
    Deployment,
    DeploymentParameters,
    TokenParameters,
    GaugePluginSet
} from "@factory/GaugesDaoFactory.sol";

// interfaces
import {
    GaugeVoterSetup,
    IGaugeVoterSetupParams
} from "@setup/GaugeVoterSetup.sol";
import {IEscrowCurveIncreasing, IEscrowCurveTokenStorage} from "@curve/IEscrowCurveIncreasing.sol";
import {IExitQueue, ITicket, IExitQueueErrorsAndEvents} from "@queue/IExitQueue.sol";
import {ILock, IWhitelistErrors, IWhitelistEvents} from "@lock/ILock.sol";
import {
    IVotingEscrowIncreasing,
    IWithdrawalQueueErrors,
    ILockedBalanceIncreasing,
    IVotingEscrowEventsStorageErrorsEvents
} from "@escrow/IVotingEscrowIncreasing.sol";
import {IGaugeVote, IGaugeVoterStorageEventsErrors} from "@voting/IGaugeVoter.sol";

import {DeployGauges} from "script/deploy/DeployGauges.s.sol";
