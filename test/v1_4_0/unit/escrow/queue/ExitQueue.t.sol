pragma solidity ^0.8.17;

import {console2 as console} from "forge-std/console2.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";
import {DAO, createTestDAO} from "@mocks/MockDAO.sol";
import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";
import {ExitQueueBase, DynamicExitQueue, IDynamicExitQueue, ITicketV2} from "./ExitQueueBase.sol";

contract TestExitQueue is ExitQueueBase {}
