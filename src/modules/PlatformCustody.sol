// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ICustody} from "../interfaces/ICustody.sol";
import {PlatformStorage} from "../storage/PlatformStorage.sol";
import {UserId, BookKey} from "../types/IdTypes.sol";
import {Side} from "../types/Enums.sol";

import {BookKeyLib} from "../encoding/BookKeyLib.sol";

import {Deposits} from "../core/Deposits.sol";

/// @notice Internal custody logic for deposits and withdrawals.
abstract contract PlatformCustody {
    // ==================== ICustody ====================

    // ==================== Write API ====================

    function _deposit(UserId uid, uint128 amount) internal {
        PlatformStorage.Layout storage s = PlatformStorage.layout();
        Deposits.doDeposit(s, uid, amount);

        emit ICustody.PointsDeposited(UserId.unwrap(uid), msg.sender, amount);
    }

    function _withdraw(UserId uid, uint128 amount) internal {
        PlatformStorage.Layout storage s = PlatformStorage.layout();
        Deposits.doWithdraw(s, uid, amount);

        emit ICustody.PointsWithdrawn(UserId.unwrap(uid), msg.sender, amount);
    }

    function _depositShares(UserId uid, uint64 marketId, uint8 outcomeId, uint128 amount) internal {
        // FIXME: impl proper bookKey / positionId.
        BookKey bookKey = BookKeyLib.pack(marketId, outcomeId, Side.Ask);

        PlatformStorage.Layout storage s = PlatformStorage.layout();
        Deposits.doSharesDeposit(s, uid, bookKey, amount);

        emit ICustody.SharesDeposited(UserId.unwrap(uid), marketId, outcomeId, amount);
    }

    function _withdrawShares(UserId uid, uint64 marketId, uint8 outcomeId, uint128 amount) internal {
        // FIXME: impl proper bookKey / positionId.
        BookKey bookKey = BookKeyLib.pack(marketId, outcomeId, Side.Ask);

        PlatformStorage.Layout storage s = PlatformStorage.layout();
        Deposits.doSharesWithdraw(s, uid, bookKey, amount);

        emit ICustody.SharesWithdrawn(UserId.unwrap(uid), marketId, outcomeId, amount);
    }
}
