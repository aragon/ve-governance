pragma solidity ^0.8.17;

// imports file allows for copying test suite independently for different modules of ve
// import files here in your tests instead of from src

// contracts
import {
    Curve,
    Curve as QuadraticIncreasingEscrow,
    Clock,
    Lock,
    ExitQueue,
    VotingEscrow,
    SimpleGaugeVoter,
    SimpleGaugeVoterSetupSeason as SimpleGaugeVoterSetup
} from "@setup/SimpleGaugeVoterSetupSeason.sol";
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
import {ISimpleGaugeVoterSetupParams} from "@setup/SimpleGaugeVoterSetupSeason.sol";
import {IEscrowCurveIncreasing, IEscrowCurveTokenStorage} from "@curve/IEscrowCurveIncreasing.sol";
import {IExitQueue, ITicket, IExitQueueErrorsAndEvents} from "@queue/IExitQueue.sol";
import {ILock, IWhitelistErrors, IWhitelistEvents} from "@lock/ILock.sol";
import {
    IVotingEscrowIncreasing,
    IWithdrawalQueueErrors,
    ILockedBalanceIncreasing,
    IVotingEscrowEventsStorageErrorsEvents
} from "@escrow/IVotingEscrowIncreasing.sol";
import {IGaugeVote, ISimpleGaugeVoterStorageEventsErrors} from "@voting/ISimpleGaugeVoter.sol";

// other
import {DeployGaugesSeason as DeployGauges} from "script/deploy/DeployGaugesSeason.s.sol";
