pragma solidity ^0.8.17;

// imports file allows for copying test suite independently for different modules of ve
// import files here in your tests instead of from src

// contracts
import {QuadraticIncreasingEscrow, Clock, Lock, ExitQueue, VotingEscrow, SimpleGaugeVoter, SimpleGaugeVoterSetupV1_4_0 as SimpleGaugeVoterSetup} from "@setup/SimpleGaugeVoterSetup_v1_4_0.sol";
import {GaugesDaoFactoryV1_4_0 as GaugesDaoFactory, Deployment, DeploymentParameters, TokenParameters, GaugePluginSet} from "@factory/GaugesDaoFactory_v1_4_0.sol";

// interfaces
import {IClock, ISeasonErrors} from "@clock/IClock_v1_4_0.sol";
import {ISimpleGaugeVoterSetupParams} from "@setup/SimpleGaugeVoterSetup_v1_4_0.sol";
import {IEscrowCurveGlobalStorage, IEscrowCurveIncreasing, IEscrowCurveTokenStorage} from "@curve/IEscrowCurveIncreasing_v1_4_0.sol";
import {IExitQueue, ITicket, IExitQueueErrorsAndEvents} from "@queue/IExitQueue.sol";
import {ILock, IWhitelistErrors, IWhitelistEvents} from "@lock/ILock.sol";
import {IMerge, ISplit, IVotingEscrowIncreasing, IWithdrawalQueueErrors, ILockedBalanceIncreasing, IVotingEscrowEventsStorageErrorsEvents, IVotingEscrowCoreErrors} from "@escrow/IVotingEscrowIncreasing_v1_4_0.sol";
import {IGaugeVote, ISimpleGaugeVoterStorageEventsErrors} from "@voting/ISimpleGaugeVoter.sol";

// other
import {DeployGaugesV1_4_0 as DeployGauges} from "script/deploy/DeployGauges_v1_4_0.s.sol";
