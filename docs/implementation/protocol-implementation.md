# Social Wisdom - Protocol Implementation

## 0. Scope

This document specifies the concrete on-chain implementation of the Social Wisdom protocol.

It covers:
- contract architecture and responsibilities,
- storage model and encoding rules,
- market lifecycle implementation,
- deposits/withdrawals and custody,
- order book internals and trading APIs,
- fees and accounting flows,
- views, events, meta-transactions,
- pausing, admin, and upgrades.

It assumes familiarity with **Protocol Overview** and **Protocol Specification**.

> **Invariants:** protocol invariants are tracked in a dedicated document (`protocol-invariants.md`). This implementation doc focuses on mechanics.

## 1. Contract Architecture

The architecture is intentionally compact: all persistent state and nearly all logic live in a single core contract, with thin wrappers around external dependencies.

### 1.1 Contract Map

#### Platform

Core protocol logic. Platform is responsible for:
- market creation and lifecycle derivation,
- order book state and matching,
- Points and shares accounting (free/reserved),
- fee calculation and accrual,
- resolution and settlement,
- custody enforcement and claims.

All protocol state is stored in Platform storage (via proxy).

#### PlatformProxy

Upgradeable proxy delegating execution to the Platform implementation.

PlatformProxy:
- holds all persistent storage,
- forwards calls to the Platform logic contract,
- enables upgrades without migrating state.

Uses a standard transparent proxy pattern.

#### CTFAdapter

A patched proxy pointing to an already-deployed **Gnosis Conditional Tokens (CTF)** contract.

CTFAdapter:
- forwards standard CTF functionality unchanged,
- restricts redemption paths so that only Platform may trigger reward redemption,
- adds no business logic beyond access control.

### 1.2 Responsibilities and Boundaries

- **Platform** is the sole source of truth and enforcer of all rules.
- **PlatformProxy** only delegates and supports upgrades.
- **CTFAdapter** only gates redemption while preserving CTF semantics.

No contract other than Platform may:
- mutate user balances,
- create or settle obligations,
- influence matching,
- trigger redemption.

### 1.3 External Dependencies

#### Gnosis Conditional Tokens (CTF)
- ERC-1155 positions,
- condition/collection/position identifiers,
- split/merge/redeem primitives.

The protocol assumes correctness of the deployed CTF contract.

#### OpenZeppelin
- proxy and upgrade utilities,
- access control primitives,
- interfaces and crypto helpers.

### 1.4 Upgrades

Platform runs behind PlatformProxy. Upgrades:
- must preserve storage layout compatibility,
- must preserve protocol behavior and economic meaning.

Detailed upgrade constraints are defined in `protocol-upgradability-specification.md`.

## 2. Data Model and Storage

All state is stored in Platform storage (behind the proxy). The layout is optimized for gas efficiency, predictable access patterns, and upgrade safety.

### 2.1 Global Configuration

Stored in Platform storage:
- **defaultCollateral**: initial backing asset for Points (fixed at deployment for v1).
- **global fee configuration**: defaults used where applicable; markets may override.
- **protocolFees**: Points-denominated fee balance held by Platform.
- **pause state**: OpenZeppelin `Pausable`.
- **roles**: Market Creator role allowlist and fee exemption mapping.

These values must remain layout-compatible across upgrades.

### 2.2 Identifiers and Typed Values

The protocol uses compact identifiers to improve packing and reduce storage writes:
- `UserId`      (uint64)
- `MarketId`    (uint64)
- `OrderId`     (uint32) - scoped per book
- `OutcomeId`   (uint8)
- `Tick`        (uint8) - [1..99]
- `Side`        (uint8) - { Ask, Bid }
- `BookKey`     (uint80)
- `LevelKey`    (uint256)
- `OrderKey`    (uint256)

Addresses are used only at external boundaries:
- deposits/withdrawals and transfers,
- signature recovery,
- external integrations.

### 2.3 User Registry

Mappings:
- `address -> UserId`
- `UserId -> address`

Properties:
- `UserId(0)` is invalid/unregistered,
- assigned monotonically,
- never reused.

All user-owned state (balances, shares custody, orders) is indexed by `UserId`.

### 2.4 Accounting Structures

Balances are tracked as **free** and **reserved**.

#### Points (per user)
- free Points
- reserved Points

Stored as a packed struct.

#### Shares (per user per book)
Per `(userId, bookKey)`:
- free shares
- reserved shares

Stored as a packed struct.

Reserved balances represent obligations and must always cover them.

### 2.5 Market Storage

Markets are indexed by `marketId` in a packed struct.

Each market stores:
- `creatorId`, `resolverId`,
- `outcomesCount`,
- `expirationAt` (0 means "no expiration"),
- `allowEarlyResolve`,
- per-market fee parameters,
- resolution flags + `winningOutcomeId` (if selected/final),
- metadata anchors: `questionHash`, `outcomesHash`.

Human-readable metadata is emitted in `MarketCreated` and not stored beyond hashes.

### 2.6 Order Book Storage

Order books are indexed by `BookKey`.

#### Masks
Per book:
- `bidsMask` (uint128)
- `asksMask` (uint128)

These may be packed into one slot.

#### Levels
Per `(bookKey, tick)`:
- `headOrderId`
- `tailOrderId`
- `totalShares` (sum of `sharesRemaining` at that level)

#### Orders
Orders are stored by `(bookKey, orderId)` and form FIFO linked lists per price level.

**Storage layout** (packing-sensitive, do not reorder):

SLOT 0 (HOT — updated on every fill):
- `sharesRemaining` (uint128) — mutable, decremented on fills
- `ownerId` (uint64 / UserId) — order owner
- `nextOrderId` (uint32 / OrderId) — FIFO linked list pointer
- `tick` (uint8 / Tick) — price level [1..99]

SLOT 1 (COLD — immutable):
- `requestedShares` (uint128) — original order size (for indexing/views)

**Note:** `side` is **not stored** in Order; it is derivable from the `BookKey` used to address the order. This avoids redundancy and saves gas.

### 2.7 Fees and Incentives Storage

- `protocolFees` (Points)
- `creatorFees[creatorId]` (Points)
- `feeExempt[userId]` (bool)

Fee balances are accounted separately from user trading balances.

### 2.8 Meta-Transaction State

- `nonces[userId] -> uint256`
- incremented on each successful signed call.

### 2.9 Storage Compatibility Rules

- struct field order must not change,
- new fields only appended,
- existing field meaning must not change.

## 3. Keys and Encoding

Composite keys are fixed, collision-free under bounded domains, and intentionally human-inspectable (bit-shift decoding is straightforward).

### 3.1 Primitive Sizes

- UserId    - 64 bits (8 bytes)
- MarketId  - 64 bits (8 bytes)
- OrderId   - 32 bits (4 bytes), scoped per BookKey
- OutcomeId - 8 bits  (1 byte)
- Side      - 8 bits  (1 byte)
- Tick      - 8 bits  (1 byte), values [1..99]
- BookKey   - 80 bits (10 bytes)

All inputs are bounds-checked before encoding.

### 3.2 BookKey Encoding (80 bits / 10 bytes)

A BookKey identifies one order book: `(marketId, outcomeId, side)`.

Bit layout (MSB -> LSB):

```
marketId (64) | outcomeId (8) | side (8)
```

Encoding:

```
bookKey = (marketId << 16) | (outcomeId << 8) | side
```

### 3.3 LevelKey Encoding (88 bits payload)

A LevelKey identifies a price level in a book: `(bookKey, tick)`.

Bit layout:

```
bookKey (80) | tick (8)
```

Encoding:

```
levelKey = (bookKey << 8) | tick
```

### 3.4 OrderKey Encoding (112 bits payload)

An OrderKey identifies an order: `(bookKey, orderId)`.

Bit layout:

```
bookKey (80) | orderId (32)
```

Encoding:

```
orderKey = (bookKey << 32) | orderId
```

OrderIds:
- monotonically increasing per book,
- never reused.

### 3.5 Tick Semantics

- Tick ∈ [1..99]
- tick unit = **centi-Points per share**
- conceptually: `1 Point ~= 1 settlement unit`, `1 tick = 0.01 Point`

Ticks are always explicit. No rounding-based implied prices exist.

### 3.6 Price Level Masks

Each book maintains:
- `asksMask` (uint128)
- `bidsMask` (uint128)

Bit `i` corresponds to tick `i`. Bit set => level non-empty.

Mask usage:
- O(1) best-price discovery via bit ops,
- deterministic iteration across active levels only.

`asksMask` and `bidsMask` can be packed into one 256-bit slot.

### 3.7 Encoding Guarantees

All encoding rules guarantee:
- no collisions within bounds,
- deterministic decoding,
- stable layout across upgrades.

## 4. Market Lifecycle Implementation

Market state is not stored as a mutable enum; it is derived deterministically from stored parameters and resolution flags.

### 4.1 Market Existence

A market exists iff:
- `marketId != 0`, and
- `marketId < nextMarketId`.

No explicit `exists` flag is stored.

### 4.2 Market Definition Parameters

Lifecycle controls defined at creation:
- `expirationAt`:
  - `0` means "no deadline" (never becomes Expired),
  - otherwise a timestamp after which trading is disabled.
- `allowEarlyResolve`:
  - if `true`, resolver may select outcome before expiration,
  - if `false` and `expirationAt != 0`, resolver may select outcome only after Expired.

All market parameters are immutable.

### 4.3 Derived States

Each market is always in exactly one state:
- Active
- Expired
- Resolved (Pending)
- Resolved (Final)

### 4.4 State Priority

1. Finalized outcome -> **Resolved (Final)**
2. Selected outcome (not finalized) -> **Resolved (Pending)**
3. `expirationAt != 0 && block.timestamp >= expirationAt` -> **Expired**
4. Otherwise -> **Active**

Resolution supersedes expiration.

### 4.5 Operational Meaning

- **Active**: place/match/cancel enabled.
- **Expired**: place/match disabled; cancel enabled.
- **Resolved (Pending)**: place/match disabled; cancel enabled; claims disabled; resolver may update outcome.
- **Resolved (Final)**: trading disabled; cancel enabled; claims enabled.

### 4.6 Transitions and Callers

- Create: Market Creator role.
- Expire: derived automatically by time (if enabled).
- Resolve (Pending): only the designated resolver; subject to `allowEarlyResolve` + `expirationAt`.
- Finalize: only the designated resolver.

## 5. Deposits, Withdrawals, and Collateral

Deposits/withdrawals are protocol-level and independent of market state (unless paused).

### 5.1 Supported Collateral

- v1 uses a configured `defaultCollateral` address.
- deposits accepted only for supported assets.
- all balances are denominated in Points regardless of deposit asset.

### 5.2 Deposits

On deposit:
- collateral transfers into protocol custody,
- Points credited to user **free** balance.

No trading obligation is created by deposit alone.

### 5.3 Withdrawals

On withdrawal:
- Points debited from user **free** balance,
- economically equivalent value transferred out.

Constraints:
- reserved balances are not withdrawable,
- withdrawals must remain backed by protocol collateral reserves,
- asset type of withdrawal may differ from original deposit (value-equivalent only).

### 5.4 Collateralization

- bids reserve Points (principal + max trading fee reservation),
- asks reserve outcome shares (plus max trading fee reservation if applicable).

No partial collateralization and no reuse of reserved balances.

### 5.5 Custody Summary

Custody exists only as required by protocol rules:
- collateral backing Points,
- reserved balances for orders,
- ERC-1155 shares deposited for trading,
- temporary custody during claim settlement.

## 6. Order Book Core

Fully on-chain deterministic LOB with strict price–time priority.

### 6.1 Scope

Each `(marketId, outcomeId, side)` maps to one `BookKey` and one order book.

### 6.2 Discrete Price Levels

- tick ∈ [1..99]
- centi-Points per share
- all orders specify explicit tick

### 6.3 Masks

`bidsMask` and `asksMask` indicate which ticks are non-empty. Used for O(1) best-price selection.

### 6.4 Levels

Per `(bookKey, tick)`:
- head, tail orderId
- totalShares

Level considered empty if `totalShares == 0` and its mask bit must be unset.

### 6.5 Orders and FIFO

Orders are FIFO within a level, stored as singly linked lists via `nextOrderId`.

**Storage packing** (see §2.6 for details):
- SLOT 0 (hot): `sharesRemaining`, `ownerId`, `nextOrderId`, `tick`
- SLOT 1 (cold): `requestedShares`

**Side derivation:** `side` is not stored in Order; it is encoded in the `BookKey` and derivable from context.

### 6.6 Cancellation (Bounded Predecessor Hints)

To avoid unbounded traversal:
- caller supplies up to 16 predecessor candidates,
- protocol picks a valid predecessor where `pred.nextOrderId == targetOrderId` and pred is active,
- rewires pointers, updates head/tail, updates totals and masks,
- releases remaining reservations.

If no valid predecessor found, cancellation reverts.

## 7. Trading APIs

All trading entry points:
- validate market existence/state,
- validate bounds and parameters,
- reserve principal + max fee,
- update order book deterministically.

### 7.1 Common Preconditions

- market exists (`marketId < nextMarketId`)
- outcomeId valid for market
- tick bounds valid (`[1..99]`)
- sufficient free balances for required reservations
- protocol not paused

### 7.2 placeLimit

Creates a limit order and optionally matches immediately.

**A new `orderId` is always allocated** on every call (even if fully filled immediately).

Behavior:
1. allocate orderId
2. validate Active
3. reserve principal + max fee
4. match against opposite side by price–time
5. if remainder: append to FIFO level, update masks
6. release unused fee reservation

### 7.3 take (Market Order)

Executes against existing liquidity; never rests in the book and does not allocate `orderId`.

Inputs include:
- `maxTick` (price bound)
- `minFill` (fill-or-revert threshold)

Behavior:
1. validate Active
2. reserve principal + max fee
3. walk levels using masks; stop at price worse than maxTick
4. if filled < minFill: revert
5. otherwise settle fills; release unused reservations

### 7.4 cancel

Removes a resting order and releases remaining reservations.

- allowed in **all** market states (including Final)
- uses bounded predecessor candidates (Section 6.6)

### 7.5 Internal Call Structure

External entry points delegate to internal `_placeLimit/_take/_cancel(userId, ...)` to support meta-txs and reduce duplication.

## 8. Fees

Fees are Points-denominated and are explicit.

### 8.1 Fee Types

- Trading fees (maker/taker)
- Winning fee (applied at claim)

### 8.2 Trading Fees (Reserve -> Charge -> Release)

- max fee is reserved upfront with principal,
- fees are charged only on executed volume,
- unused reserved fee is released on cancel/partial execution.

Trading fees are charged **in addition** to the exchanged trade amounts (fees do not distort price formation).

### 8.3 Winning Fee

- charged only at claim time,
- deducted from gross payout,
- never reserved in advance.

### 8.4 Accrual

- `protocolFees` (Points) — accrued from trading fees
- `creatorFees[creatorId]` (Points) — creator share of trading fees

### 8.5 Fee Exemptions

- `feeExempt[userId]` bypasses trading + winning fees (lookup via user registry).
- dust handling is unaffected.

### 8.6 Dust

Discrete prices and integer arithmetic may produce dust.
Dust is accumulated in favor of the protocol to ensure deterministic settlement and avoid blocked claims.

## 9. Views and Read APIs

Views are canonical for reading state (events are not).

Exposed view categories:
- market config + derived state,
- balances (Points and shares: free/reserved),
- order book (masks, levels, orders),
- cancellation helper views (candidate predecessors),
- fee balances (protocol and creator),
- fee exemption status,
- per-user nonces.

Views remain callable regardless of market state (unless explicitly restricted).

## 10. Events

Events are for observation and indexing; storage/views are canonical.

> Solidity code blocks use ````solidity` fences in this document.

### 10.0 Identity Convention (UserId-first)

High-frequency events prefer `UserId` for compactness. Address ↔ UserId is established via `UserRegistered` and `userOfId(userId)`.

### 10.1 User Registry Events

```solidity
event UserRegistered(
    address indexed user,
    uint64 userId
);
```

Emitted once per address when a fresh `userId` is assigned (lazy registration allowed).

### 10.2 Market Lifecycle Events

```solidity
event MarketCreated(
    uint64 indexed marketId,
    uint64 indexed creatorId,
    uint64 indexed resolverId,
    uint64 expirationAt,
    bool allowEarlyResolve,
    bytes32 questionHash,
    bytes32 outcomesHash,
    string question,
    string[] outcomeLabels,
    string resolutionRules
);
```

Emitted once after market storage is written.

```solidity
event MarketResolved(
    uint64 indexed marketId,
    uint8 winningOutcomeId,
    uint64 resolvedAt
);
```

Emitted when resolver selects (or updates) the pending outcome.

```solidity
event MarketFinalized(
    uint64 indexed marketId,
    uint64 finalizedAt
);
```

Emitted once when resolver finalizes the outcome.

### 10.3 Trading Events

```solidity
event OrderPlaced(
    uint64 indexed marketId,
    uint8  indexed outcomeId,
    uint64 indexed ownerId,
    uint8 side,
    uint32 orderId,
    uint8 tick,
    uint128 sharesRequested
);
```

Emitted on every `placeLimit` after allocating `orderId`, before any `Trade` events.

```solidity
event OrderCancelled(
    uint64 indexed marketId,
    uint8  indexed outcomeId,
    uint64 indexed ownerId,
    uint8 side,
    uint32 orderId,
    uint8 tick,
    uint128 sharesCancelled
);
```

Emitted after successful cancellation and release of reservations.

```solidity
event Trade(
    uint64 indexed marketId,
    uint64 indexed makerId,
    uint64 indexed takerId,
    uint8 outcomeId,
    uint8 side,
    uint32 makerOrderId,
    uint32 takerOrderId,
    uint8 tick,
    uint128 sharesFilled,
    uint128 pointsExchanged,
    uint128 makerFeePaid,
    uint128 takerFeePaid
);
```

Emitted once per maker fill step after balances update.
`takerOrderId = 0` for pure `take`. Non-zero for `placeLimit`-initiated trades.

```solidity
event Take(
    uint64 indexed marketId,
    uint8  indexed outcomeId,
    uint64 indexed takerId,
    uint8 side,
    uint8 maxTick,
    uint128 sharesRequested,
    uint128 sharesFilled
);
```

Emitted once per `take`, after all `Trade` events of that call.

### 10.4 Balance and Custody Events

```solidity
event PointsDeposited(
    uint64 indexed userId,
    address user,
    uint128 amount
);
```

Emitted after collateral transfer succeeds and Points are credited.

```solidity
event PointsWithdrawn(
    uint64 indexed userId,
    address user,
    uint128 amount
);
```

Emitted after Points debit and collateral transfer succeeds.

```solidity
event SharesDeposited(
    uint64 indexed userId,
    uint64 indexed marketId,
    uint8 indexed outcomeId,
    uint128 amount
);
```

Emitted after ERC-1155 transfer into custody succeeds.

```solidity
event SharesWithdrawn(
    uint64 indexed userId,
    uint64 indexed marketId,
    uint8 indexed outcomeId,
    uint128 amount
);
```

Emitted after balances debit and ERC-1155 transfer out succeeds.

### 10.5 Claim Events

```solidity
event Claimed(
    uint64 indexed marketId,
    uint64 indexed userId,
    uint128 sharesRedeemed,
    uint128 grossPoints,
    uint128 winningFeePaid,
    uint128 netPoints
);
```

Emitted after successful claim settlement.

### 10.6 Administrative Events

Protocol uses OZ `Pausable`:
- `Paused(address indexed account)`
- `Unpaused(address indexed account)`

```solidity
event FeeExemptionUpdated(
    address indexed account,
    bool isExempt
);
```

Emitted after fee exemption state changes.

### 10.7 Emission Ordering

- `placeLimit`: `OrderPlaced` -> `Trade`(s)
- `take`: `Trade`(s) -> `Take`
- `cancel`: `OrderCancelled`

## 11. Meta-Transactions

Meta-transactions add signature-based entry points without changing protocol semantics.

### 11.1 Principle

For each state-changing method `X(...)`, provide:
- `XWithSig(user, ..., signature)`

Recovered signer becomes the effective user; `msg.sender` is the relayer.

### 11.2 Signed Payload

Signed payload includes:
- method identifier + parameters,
- chainId,
- verifying contract address,
- per-user nonce.

EIP-712 typed data (or equivalent) is used to prevent cross-chain/contract replays.

### 11.3 Nonces

- stored per `userId`,
- incremented exactly once on successful signed execution,
- unchanged on revert.

### 11.4 Internal Structure

Both direct and signature entry points call the same internal functions, passing explicit `userId`.

## 12. Pausing, Administration, and Upgradability

### 12.1 Pausing

Uses OZ `Pausable`.

When paused:
- all state-changing operations are disabled (deposits, withdrawals, trading, cancellation, claims, market creation, resolution/finalization),
- views remain available.

Pausing never moves funds or changes balances.

### 12.2 Owner Powers

Owner may:
- pause/unpause,
- manage fee exemptions,
- manage Market Creator role,
- upgrade Platform logic via proxy.

Owner cannot:
- move user funds,
- resolve/finalize markets,
- modify market parameters post-creation.

### 12.3 Upgrades

Upgrades are executed by Owner via proxy mechanisms and must preserve storage compatibility and economic meaning.
