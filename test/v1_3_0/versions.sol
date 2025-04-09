pragma solidity ^0.8.17;

// imports file allows for copying test suite independently for different modules of ve
// import files here in your tests instead of from src

// contracts
import {
    Clock,
    Lock,
    Curve,
    Curve as LinearIncreasingEscrow,
    Curve as QuadraticIncreasingEscrow,
    ExitQueue,
    VotingEscrow,
    EscrowIVotesAdapter,
    SimpleGaugeVoter,
    SimpleGaugeVoterSetupV1_3_0 as SimpleGaugeVoterSetup
} from "@setup/SimpleGaugeVoterSetup_v1_3_0.sol";
import {
    GaugesDaoFactoryV1_3_0 as GaugesDaoFactory,
    Deployment,
    DeploymentParameters,
    TokenParameters,
    GaugePluginSet
} from "@factory/GaugesDaoFactory_v1_3_0.sol";

// interfaces
import {IClockV1_3_0 as IClock} from "@clock/IClock_v1_3_0.sol";
import {ISeasonErrors} from "@clock/IClockSeason.sol";
import {ISimpleGaugeVoterSetupParams} from "@setup/SimpleGaugeVoterSetup_v1_3_0.sol";
import {
    IEscrowCurveGlobalStorage,
    IEscrowCurveIncreasingV1_3_0 as IEscrowCurveIncreasing,
    IEscrowCurveTokenStorage,
    IEscrowCurveGlobalStorage
} from "@curve/IEscrowCurveIncreasing_v1_3_0.sol";
import {IExitQueue, ITicket, IExitQueueErrorsAndEvents} from "@queue/IExitQueue.sol";
import {ILock, IWhitelistErrors, IWhitelistEvents} from "@lock/ILock.sol";
import {
    IMerge,
    ISplit,
    IVotingEscrowIncreasing,
    IWithdrawalQueueErrors,
    ILockedBalanceIncreasing,
    IVotingEscrowEventsStorageErrorsEvents,
    IVotingEscrowCoreErrors,
    IMergeEventsAndErrors,
    ISplitEventsAndErrors
} from "@escrow/IVotingEscrowIncreasing_v1_3_0.sol";
import {IGaugeVote, ISimpleGaugeVoterStorageEventsErrors} from "@voting/ISimpleGaugeVoter.sol";
import {
    IEscrowIVotesAdapterStorage,
    IEscrowIVotesAdapterErrorsAndEvents
} from "@delegation/IEscrowIVotesAdapter.sol";

// other
import {DeployGaugesV1_3_0 as DeployGauges} from "script/deploy/DeployGauges_v1_3_0.s.sol";
