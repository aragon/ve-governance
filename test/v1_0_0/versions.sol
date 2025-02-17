pragma solidity ^0.8.17;

// imports file allows for copying test suite independently for different modules of ve
// import files here in your tests instead of from src

// contracts
import {Clock} from "@clock/Clock.sol";
import {Lock} from "@escrow/Lock.sol";
import {ExitQueue} from "@escrow/ExitQueue.sol";
import {VotingEscrow} from "@escrow/VotingEscrowIncreasing.sol";
import {SimpleGaugeVoter} from "@voting/SimpleGaugeVoter.sol";
import {SimpleGaugeVoterSetup} from "@voting/SimpleGaugeVoterSetup.sol";
import {QuadraticIncreasingEscrow} from "@escrow/QuadraticIncreasingEscrow.sol";

// interfaces
import {SimpleGaugeVoterSetup, ISimpleGaugeVoterSetupParams} from "@voting/SimpleGaugeVoterSetup.sol";
import {IEscrowCurveIncreasing, IEscrowCurveTokenStorage} from "@escrow-interfaces/IEscrowCurveIncreasing.sol";
import {IExitQueue, ITicket, IExitQueueErrorsAndEvents} from "@escrow-interfaces/IExitQueue.sol";
import {ILock, IWhitelistErrors, IWhitelistEvents} from "@escrow-interfaces/ILock.sol";
import {IVotingEscrowIncreasing, IWithdrawalQueueErrors, ILockedBalanceIncreasing, IVotingEscrowEventsStorageErrorsEvents} from "@escrow-interfaces/IVotingEscrowIncreasing.sol";
import {IGaugeVote, ISimpleGaugeVoterStorageEventsErrors} from "@voting/ISimpleGaugeVoter.sol";
