// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IAdmin} from "./IAdmin.sol";
import {IAccounting} from "./IAccounting.sol";
import {ICustody} from "./ICustody.sol";
import {IMarkets} from "./IMarkets.sol";
import {ITrading} from "./ITrading.sol";

/// @notice IPlatform aggregates all domain interfaces for the Social Wisdom protocol.
/// All events and function signatures for user-facing operations.
/// Events are primary for observation/indexing; views provide canonical state.
interface IPlatform is IMarkets, ITrading, IAccounting, ICustody, IAdmin {}
