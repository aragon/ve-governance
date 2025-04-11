pragma solidity ^0.8.17;

// imports file allows for copying test suite independently for different modules of ve
// import files here in your tests instead of from src

// contracts
import {
    Curve,
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
import {GaugeVoterSetup, IGaugeVoterSetupParams} from "@setup/GaugeVoterSetup.sol";
import {IEscrowCurveIncreasing, IEscrowCurveTokenStorage} from "@curve/IEscrowCurveIncreasing.sol";
import {IExitQueue, ITicket, IExitQueueErrorsAndEvents} from "@queue/IExitQueue.sol";
import {ILock, IWhitelistErrors, IWhitelistEvents} from "@lock/ILock.sol";
import {
    IVotingEscrowIncreasing,
    IWithdrawalQueueErrors,
    ILockedBalanceIncreasing,
    IVotingEscrowEventsStorageErrorsEvents
} from "@escrow/IVotingEscrowIncreasing.sol";
import {
    ITokenGaugeVote as IGaugeVote,
    ITokenGaugeVoterStorageEventsErrors as IGaugeVoterStorageEventsErrors
} from "@voting/ITokenGaugeVoter.sol";

import {DeployGauges} from "script/deploy/DeployGauges.s.sol";

// deprecated but to avoid rewriting all tests
// housekeeping: remove these as we go
import {
    Curve as QuadraticIncreasingEscrow,
    GaugeVoter as SimpleGaugeVoter,
    GaugeVoterSetup as SimpleGaugeVoterSetup,
    IGaugeVoterSetupParams as ISimpleGaugeVoterSetupParams
} from "@setup/GaugeVoterSetup.sol";

import {
    ITokenGaugeVoterStorageEventsErrors as ISimpleGaugeVoterStorageEventsErrors
} from "@voting/ITokenGaugeVoter.sol";
