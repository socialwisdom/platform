# Social Wisdom — Prediction Markets MVP
## Architecture, Storage Layout, and Implementation Guide

This document is the canonical reference for the Social Wisdom MVP.
It defines what is built, why, and how it is implemented — down to storage layout, typed keys, and events.

The MVP is explicitly designed to operate without any backend. As a consequence:
- Matching and settlement are performed on-chain.
- Market metadata is emitted in events and reconstructed by indexers / UIs.
- Gas is accepted as a tradeoff for determinism and backend-free operation.
- Some features are intentionally rigid (e.g., discrete ticks, strict gating) to avoid off-chain coordination.

The design is intentionally explicit, strict, and conservative.

---

## 0. Introduction

Social Wisdom is a prediction market platform based on the thesis:
markets aggregate collective knowledge.

This MVP implements:
- on-chain prediction markets,
- a fully on-chain deterministic limit order book,
- real outcome shares via Gnosis Conditional Tokens (CTF),
- internal accounting units (“Points”),
- protocol-enforced fees applied at redemption time.

Expected later evolution:
- oracle-based resolution,
- off-chain matching with on-chain settlement,
- fee model changes,
- upgraded custody/adapter logic.

---

## 1. High-level design

### 1.1 Core idea
- Users trade outcome shares against Points.
- Shares represent real-world outcomes.
- Points are internal accounting units, redeemable 1:1 against a settlement asset.
- Redemption of resolved positions is gated through the protocol.

This is not an AMM.
This is a deterministic price–time–priority order book.

### 1.2 Conditional Tokens usage
The protocol uses Gnosis Conditional Tokens but never exposes them directly.

Instead:
- all interactions go through a custom CTF Adapter,
- users may split/merge positions before resolution,
- redemption is restricted: only the Social Wisdom `ORDER_BOOK` can trigger it.

This gating is a core trust assumption.

---

## 2. Units and accounting

### 2.1 Points
Points are the internal unit of account:
- fixed decimals (typically 6),
- used for pricing, balances, fees, payouts,
- treated as an internal ledger unit.

Per user:
- free Points (available),
- reserved Points (locked in orders).

### 2.2 Packed storage for Points (typed)
Rule: everything packed into a single slot must be represented as a typed struct.

```solidity
struct PackedPoints {
    uint128 free;
    uint128 reserved;
}

mapping(uint64 => PackedPoints) points;
```

---

## 3. User identity optimization

To reduce gas and storage footprint, the protocol uses internal user IDs.

```solidity
type UserId is uint64;

mapping(address => UserId) userIdOf; // UserId(0) = unregistered
mapping(UserId => address) userOfId;
UserId nextUserId = UserId.wrap(1);
```

Orders store UserId instead of address.
Addresses are still emitted in events.

---

## 4. Markets

### 4.1 Market identity

Each market has:
- marketId: uint64,
- fixed outcomes count,
- immutable resolver,
- creator,
- lifecycle timestamps,
- fee configuration.

Human-readable metadata (question, outcomes, rules) is emitted in events and referenced by hashes.

### 4.2 Market storage layout

```solidity
struct MarketPacked {
    // slot 0
    address resolver;
    address creator;

    // slot 1
    uint64 createdAt;
    uint64 inactiveAfter;
    uint64 createdBlock;
    uint8  outcomesCount;
    uint8  status;          // MarketStatus
    uint8  winningOutcome;
    bool   allowEarlyResolve;

    // slot 2
    uint64 resolvedAt;
    uint64 payoutsReadyAt;

    // slot 3
    uint16 makerFeeBps;
    uint16 takerFeeBps;
    uint16 winningFeeBps;
    uint16 creatorFeeShareBps;
}

mapping(uint64 => MarketPacked) markets;

mapping(uint64 => bytes32) questionHash;
mapping(uint64 => bytes32) outcomesHash;
mapping(uint64 => bytes32) rulesHash;
```

### 4.3 Market lifecycle

```solidity
enum MarketStatus {
    Active,
    ResolvedPendingPayouts,
    ResolvedReady
}
```

- Active: trading enabled, withdrawals enabled, block.timestamp < inactiveAfter
- Inactive (implicit): trading disabled, withdrawals disabled, cancel allowed, block.timestamp >= inactiveAfter
- ResolvedPendingPayouts: outcome selected but mutable, withdrawals disabled
- ResolvedReady: payouts enabled, users may claim

---

## 5. Shares custody

### 5.1 Shares accounting (typed)

Shares are ERC1155 positions held in protocol custody.

```solidity
struct PackedShares {
    uint128 free;
    uint128 reserved;
}

mapping(uint256 => PackedShares) shares;
```

Key is composite:

```text
sharesKey = (userId << BOOKKEY_BITS) | bookKey
```

### 5.2 BookKey (typed)

Each order book corresponds to (marketId, outcomeId, side).

```solidity
enum Side { Ask, Bid }
type BookKey is uint80; // enough for packing: marketId(64) + outcomeId(8) + side(8)
```

Packed layout:

```text
BookKey =
    marketId  << 16 |
    outcomeId << 8  |
    side
```

### 5.3 depositShares / withdrawShares
- depositShares: always allowed
- withdrawShares: only while:
  - market is Active
  - block.timestamp < inactiveAfter

After inactivity or resolution, shares are frozen.

---

## 6. Order book design (core)

### 6.1 Discrete ticks and masks

Ticks are discrete:
- tick ∈ [1..99]
- meaning: Points cents per 1 share

Each book maintains:
- bidsMask, asksMask (uint128)
- bit i is set if tick level i is non-empty

This yields O(1) best-price lookup via bit operations.

### 6.2 Level storage (typed keys)

```solidity
type Tick is uint8;      // 1..99
type LevelKey is uint256;

struct Level {
    uint32  headOrderId;
    uint32  tailOrderId;
    uint128 totalShares;
}

mapping(LevelKey => Level) levels;
```

Derivation:

```text
levelKey = (bookKey << 8) | tick
```

### 6.3 Order storage (typed keys + tick on order)

Orders form a linked list per price level (price–time priority).

```solidity
type OrderId is uint32;
type OrderKey is uint256;

struct Order {
    UserId ownerId;

    Tick tick;                // explicit: order belongs to a tick level
    OrderId nextOrderId;

    uint128 requestedShares;  // immutable original size
    uint128 sharesRemaining;  // decreases on fills
}

mapping(OrderKey => Order) orders;
```

Derivation:

```text
orderKey = (bookKey << 32) | orderId
```

Notes:
- orderId monotonically increases per book
- requestedShares immutable; sharesRemaining decreases
- tick is stored explicitly for debugging and event emission clarity

### 6.4 Matching logic (high-level)

**placeLimit**

1. Verify market Active
2. Attempt immediate matching against opposite side
3. If remainder:
   - create order
   - append to level
   - update masks
4. Lock Points or Shares accordingly

**take**

1. Walk best prices using masks
2. Fill maker orders sequentially
3. Emit Trade events
4. Apply taker fee
5. Revert only if filled < minFill

### 6.5 Partial-fill control for take (minFill)

```solidity
function take(
    ...,
    uint128 sharesRequested,
    uint128 minFill
)
```

Semantics:
- attempts to fill up to sharesRequested
- if total filled < minFill, revert
- otherwise succeed, even if not fully filled

MVP default: minFill = sharesRequested (100% fill-or-revert)

---

## 7. Fees

### 7.1 Trading fees

Per market configurable:

- Maker fee (Points)
- Taker fee (Points)

### 7.2 Winning fee

Applied at claim time via gated redemption.

Accounting:

```solidity
uint128 protocolFeesAccrued;
mapping(uint64 => uint128) creatorFeesAccrued; // marketId => Points
```

Fee whitelist can exempt addresses from all fees.

---

## 8. Resolution & redemption

### 8.1 Resolver powers

Resolver may:

- resolve before inactive if allowEarlyResolve,
- change outcome while pending,
- enable payouts after resolution.

Protocol owner cannot resolve markets.

### 8.2 Redemption gating

CTF Adapter enforces:

```solidity
require(msg.sender == ORDER_BOOK);
```

Users cannot redeem directly.

### 8.3 Claim flow
1. User deposits winning shares
2. Calls claim(marketId)
3. Adapter redeems shares → Points
4. Winning fee applied (unless whitelisted)
5. Net Points credited

---

## 9. Gasless / meta-transactions

Every state-changing method has a signature-based variant:

```solidity
function placeLimitWithSig(address user, ..., bytes signature)
```

Recovered signer replaces msg.sender.

---

## 10. Emergency pause

Owner may pause the protocol.

When paused:

- trading disabled,
- deposits disabled,
- claims disabled.

Owner cannot move user funds.

---

## 11. Roles & Permissions

### 11.1 Owner

Purpose: emergency control only.

- pause/unpause the protocol

Restrictions:
- cannot create markets, resolve markets, change resolvers
- cannot move user balances or shares
- cannot change market params

### 11.2 Market Creator

Purpose: permissioned creation of new markets.

Powers:
- create markets and set all parameters at creation:
  - inactiveAfter, allowEarlyResolve
  - fees: makerFeeBps, takerFeeBps, winningFeeBps, creatorFeeShareBps
  - resolver, outcomes count, metadata (via events)

Restrictions:
- no trading privileges
- cannot modify market after creation
- cannot pause protocol

### 11.3 Resolver

Purpose: authoritative outcome selection per market (immutable).

Powers:
- resolve(outcomeId)
- change outcome while pending (per spec rules)
- enablePayouts()

Restrictions:
- resolver cannot be changed
- no access to user funds
- cannot bypass fees

### 11.4 Fee Admin (optional)

Purpose: fee whitelist management.

Powers:
- add/remove addresses from fee whitelist

Restrictions:
- cannot change market configuration
- cannot resolve markets
- cannot move funds

---

## 12. Market Creator Fee Model

Market creators earn a share of winning fees for markets they create.

At market creation:
- winningFeeBps — total payout fee (e.g., 200 = 2%)
- creatorFeeShareBps — creator share of winning fee (e.g., 2500 = 25%)

Constraints:
- immutable after creation
- creatorFeeShareBps applies only to winning fee, not trading fees

Example:
- winningFee = 2%
- creatorFeeShare = 25%
→ creator receives 0.5%, protocol receives 1.5%

Accrual at claim:
1. compute winning fee from gross payout
2. compute creator’s share
3. update:

```solidity
mapping(uint64 => uint128) creatorFeesAccrued;
uint128 protocolFeesAccrued;
```

Creator fees are withdrawable via a dedicated function (or future settlement layer).

---

## 13. Fee Whitelist Semantics

Whitelisted addresses are exempt from all protocol-level fees:

- maker trading fees,
- taker trading fees,
- winning (redeem) fees.

If whitelisted:

- trades occur at face value,
- claims pay out without fee deductions,
- creator fee shares are also skipped for that claim.

Whitelist is global (not per-market). It does not affect:

- price formation,
- order priority,
- lifecycle rules,
- permissions beyond fee exemption.

Administration:

- add/remove by FeeAdmin
- changes apply immediately
- no retroactive refunds

Implementation:

```solidity
if (isFeeWhitelisted[user]) {
    fee = 0;
} else {
    fee = calculateFee(...);
}
```

---

## 14. Event Schema

Events must allow indexers to reconstruct lifecycle, history, and order book activity.
Large metadata is emitted once at creation.

### 14.1 Market events

MarketCreated (once):

```solidity
event MarketCreated(
    uint64 indexed marketId,
    address indexed creator,
    address indexed resolver,
    uint64 createdBlock,
    uint64 inactiveAfter,
    string question,
    string[] outcomeLabels,
    string resolveRules
);
```

MarketResolved:

```solidity
event MarketResolved(
    uint64 indexed marketId,
    uint8 winningOutcome,
    uint64 resolvedAt
);
```

MarketPayoutsEnabled:

```solidity
event MarketPayoutsEnabled(
    uint64 indexed marketId,
    uint64 payoutsReadyAt
);
```

### 14.2 Order book events

OrderPlaced:

```solidity
event OrderPlaced(
    uint64 indexed marketId,
    uint8 indexed outcomeId,
    Side indexed side,
    uint32 orderId,
    address owner,
    uint8 tick,
    uint128 sharesAmount
);
```

OrderCancelled:

```solidity
event OrderCancelled(
    uint64 indexed marketId,
    uint32 indexed orderId,
    address indexed owner,
    uint128 sharesCancelled
);
```

Trade:

```solidity
event Trade(
    uint64 indexed marketId,
    uint8 indexed outcomeId,
    Side indexed side,
    uint32 makerOrderId,
    uint32 takerOrderId, // 0 = pure take
    address maker,
    address taker,
    uint8 tick,
    uint128 sharesFilled,
    uint128 pointsPaid
);
```

Take:

```solidity
event Take(
    uint64 indexed marketId,
    uint8 indexed outcomeId,
    Side indexed side,
    address indexed taker,
    uint128 sharesRequested,
    uint128 sharesFilled
);
```

### 14.3 Custody events

```solidity
event SharesDeposited(uint64 indexed marketId, uint8 indexed outcomeId, address indexed user, uint128 amount);
event SharesWithdrawn(uint64 indexed marketId, uint8 indexed outcomeId, address indexed user, address to, uint128 amount);
```

### 14.4 Claim events

```solidity
event Claimed(
    uint64 indexed marketId,
    address indexed user,
    uint128 sharesRedeemed,
    uint128 grossPoints,
    uint128 feePoints,
    uint128 netPoints
);
```

### 14.5 Balance events (optional)

```solidity
event PointsDeposited(address indexed user, uint128 amount);
event PointsWithdrawn(address indexed user, uint128 amount);
```

### 14.6 Admin events

```solidity
event FeeWhitelistUpdated(address indexed account, bool isWhitelisted);
event ProtocolPaused(address indexed by);
event ProtocolUnpaused(address indexed by);
```

Indexer guidance:
- trust storage for current state,
- use events for history/UX analytics,
- market metadata comes from MarketCreated anchored by createdBlock.

---

## 15. Invariants

Violating any invariant is a correctness bug and/or a security issue.

**A. Accounting**
1. Non-negativity: no underflows.
2. Conservation (Points): absent fees, matching transfers Points without creating/destroying.
3. Conservation (Shares): matching transfers shares without creating/destroying ERC1155 positions.
4. Reserve correctness: resting orders are fully collateralized by reserved Points/Shares.
5. No double-spend: free + reserved changes only via explicit state transitions.

**B. Market lifecycle**
6. Immutability: market params (resolver, fees, outcome count, hashes) immutable.
7. Freeze rule: after inactiveAfter or once resolved, share withdrawals disabled.
8. Resolution gating: claims only in ResolvedReady.

**C. Redemption gating**
9. Only ORDER_BOOK may redeem via adapter.
10. Fees enforced at claim: winning fees applied only during claim, never bypassable.

**D. Order book**
11. Tick bounds: tick in [1..99].
12. Mask correctness: masks match empty/non-empty levels.
13. Linked-list integrity: head/tail correctness and termination.
14. Level totals: totalShares equals sum(sharesRemaining) in level.
15. Price–time priority: best price then FIFO within level.

**E. take(minFill)**
16. take reverts iff filled < minFill.

**F. Whitelist**
17. All-or-nothing fees: maker/taker/winning fees are all zero.
18. No privilege bleed: whitelist never changes permissions/lifecycle.

---

## 16. Future work
- Oracle-based resolution
- Off-chain matching
- Batch operations
- Multiple settlement assets
- Dispute resolution.

```
