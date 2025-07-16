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
    GaugeVoterSetupSeason as GaugeVoterSetup
} from "@setup/GaugeVoterSetupSeason.sol";
import {
    GaugesDaoFactorySeason as GaugesDaoFactory,
    Deployment,
    DeploymentParameters,
    TokenParameters,
    GaugePluginSet
} from "@factory/GaugesDaoFactorySeason.sol";

// interfaces
import {IClock} from "@clock/IClock.sol";
import {ISeasonErrors} from "@clock/IClockSeason.sol";
import {IGaugeVoterSetupParams} from "@setup/GaugeVoterSetupSeason.sol";
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

// other
import {DeployGaugesSeason as DeployGauges} from "script/deploy/DeployGaugesSeason.s.sol";

// deprecated but to avoid rewriting all tests
// housekeeping: remove these as we go
import {
    Curve as QuadraticIncreasingEscrow,
    GaugeVoter as SimpleGaugeVoter,
    GaugeVoterSetupSeason as SimpleGaugeVoterSetup,
    IGaugeVoterSetupParams as ISimpleGaugeVoterSetupParams
} from "@setup/GaugeVoterSetupSeason.sol";

import {
    ITokenGaugeVoterStorageEventsErrors as ISimpleGaugeVoterStorageEventsErrors
} from "@voting/ITokenGaugeVoter.sol";
