pragma solidity ^0.8.17;

// imports file allows for copying test suite independently for different modules of ve
// import files here in your tests instead of from src

// contracts
import {QuadraticIncreasingEscrow, Clock, Lock, ExitQueue, VotingEscrow, SimpleGaugeVoter, SimpleGaugeVoterSetupV1_1_0 as SimpleGaugeVoterSetup} from "@setup/SimpleGaugeVoterSetup_v1_1_0.sol";
import {GaugesDaoFactoryV1_1_0 as GaugesDaoFactory, Deployment, DeploymentParameters, TokenParameters, GaugePluginSet} from "@factory/GaugesDaoFactory_v1_1_0.sol";

// interfaces
import {ISimpleGaugeVoterSetupParams} from "@setup/SimpleGaugeVoterSetup_v1_1_0.sol";
import {IEscrowCurveIncreasing, IEscrowCurveTokenStorage} from "@curve/IEscrowCurveIncreasing.sol";
import {IExitQueue, ITicket, IExitQueueErrorsAndEvents} from "@queue/IExitQueue.sol";
import {ILock, IWhitelistErrors, IWhitelistEvents} from "@lock/ILock.sol";
import {IVotingEscrowIncreasing, IWithdrawalQueueErrors, ILockedBalanceIncreasing, IVotingEscrowEventsStorageErrorsEvents} from "@escrow/IVotingEscrowIncreasing.sol";
import {IGaugeVote, ISimpleGaugeVoterStorageEventsErrors} from "@voting/ISimpleGaugeVoter.sol";

// other
import {DeployGaugesV1_1_0 as DeployGauges} from "script/deploy/DeployGauges_v1_1_0.s.sol";
