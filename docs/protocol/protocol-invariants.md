# Social Wisdom - Protocol Invariants

## 0. Scope

This document lists the protocol invariants that must hold across **all** implementations and upgrades.

Invariants are grouped by subsystem:
- accounting and collateralization,
- markets and lifecycle,
- order book integrity,
- fees and settlement,
- custody and withdrawals,
- meta-transactions,
- administration and upgrades.

If an invariant can be violated, it is a correctness and/or security bug.

This document intentionally avoids repeating full behavioral rules.
Those belong in:
- `protocol-overview.md`
- `protocol-specification.md`
- `protocol-implementation.md`

## 1. Accounting and Collateralization

### 1.1 Non-negativity
- All balances are non-negative at all times.
- No underflows are possible in Points or shares accounting.

### 1.2 Free + Reserved Conservation (per asset type)
For each user and asset type:
- `total = free + reserved`
- total changes only via explicit, protocol-defined transitions (deposit, withdrawal, trade, claim, fee accrual).

### 1.3 No Double-Spend
- A unit of value cannot be simultaneously counted as both free and reserved.
- Reserved balances cannot be withdrawn or reused to collateralize additional obligations.

### 1.4 Full Collateralization of Obligations
- Every open obligation is fully collateralized at creation time.
- Bid-side obligations reserve enough Points to cover worst-case execution under allowed parameters.
- Ask-side obligations reserve enough shares to cover worst-case execution under allowed parameters.

### 1.5 Deterministic State Transitions
- For the same input and the same prior state, accounting transitions produce the same result.
- No off-chain coordination is required for correctness.

## 2. Markets and Lifecycle

### 2.1 Market Existence
- A non-existent marketId is never processed beyond existence checks.
- Once created, a market always exists (no deletion).

### 2.2 Parameter Immutability
Market parameters do not change after creation, including:
- outcomes count and identity anchors (hashes),
- resolver identity,
- fee parameters,
- lifecycle configuration (`expirationAt`, `allowEarlyResolve`).

### 2.3 Single State at a Time
- Each market is always in exactly one derived lifecycle state.

### 2.4 Monotonic Progression
- Market state never transitions backward.
- Final resolution is terminal.

### 2.5 Resolution Authority
- Only the designated resolver can select/update the winning outcome.
- Only the designated resolver can finalize the outcome.

### 2.6 Finality Boundary
- Claims (settlement) are possible if and only if the market is **Resolved (Final)**.
- Winning outcome selection in **Resolved (Pending)** is not claimable.

## 3. Order Book Integrity

### 3.1 Tick Bounds
- Every tick used by the order book is within `[1..99]`.
- No implicit rounding creates an out-of-range tick.

### 3.2 Price–Time Priority
Matching always respects:
1. price priority (best price first),
2. time priority (FIFO order of creation at the same price level).

No operation may reorder resting orders within a tick level.

### 3.3 Linked List Correctness (Per Level)
For each price level:
- the list is acyclic and terminates,
- head/tail pointers are consistent,
- every order reachable from head belongs to that level.

### 3.4 Level Totals Correctness
For each price level:
- `totalShares` equals the sum of `sharesRemaining` over all active orders in that level.

### 3.5 Mask Correctness
For each book and side mask:
- a bit is set iff the corresponding price level is non-empty.
- best-price discovery via masks never skips a non-empty level.

### 3.6 Order Identity and Uniqueness
- `placeLimit` always allocates a fresh `orderId` (even if fully filled immediately).
- OrderIds are monotonically increasing per BookKey and never reused.
- `take` never allocates an orderId.

### 3.7 sharesRemaining Monotonicity
- `sharesRemaining` decreases on fills and never increases.
- `requestedShares` is immutable.

### 3.8 Cancellation Safety
- Cancelling an order releases only the remaining obligation of that order.
- Cancellation cannot corrupt list structure, totals, or masks.
- Cancellation cannot release balances that have already been exchanged via fills.

## 4. Trading Semantics

### 4.1 Active-State Matching
- Matching and new order placement occur only when the market is in **Active** state.

### 4.2 Take Price Bound
- `take` never executes beyond its specified `maxTick` constraint.

### 4.3 MinFill Semantics
- `take` reverts iff `filled < minFill`.
- Otherwise, partial execution is permitted.

### 4.4 No Uncollateralized Execution
- A trade cannot execute unless both sides are fully collateralized by reserved balances.

## 5. Fees, Dust, and Accrual

### 5.1 Trading Fees Are Realization-Based
- Trading fees are charged only on executed volume.
- Unexecuted intent does not incur trading fees.

### 5.2 Trading Fee Reservation Safety
- When required by the design, trading fees are reserved upfront and released if execution does not occur.
- Reserved fees cannot be withdrawn while reserved.

### 5.3 Winning Fee Is Claim-Only
- Winning fee is applied only at claim time.
- Winning fee is deducted from the gross payout atomically.
- Winning fee is never applied during trading and never influences execution prices.

### 5.4 Fee Exemption Is Strict and Limited
- Fee-exempt accounts pay zero trading fees and zero winning fees.
- Fee exemption does not change permissions, lifecycle, or order priority.
- Dust handling is not affected by fee exemption.

### 5.5 Fee Accounting Separation
- Protocol and creator fee balances are accounted separately from user trading balances.
- Fee withdrawal mechanisms do not affect user balances except through explicit, accounted transfers.

### 5.6 Dust Determinism
- Dust outcomes are deterministic given the same inputs and state.
- Dust cannot block claims or settlement flows.
- Dust accrues to the protocol by rule, not by discretion.

## 6. Custody, Deposits, and Withdrawals

### 6.1 Explicit Custody Only
- Assets enter protocol custody only via explicit protocol-defined actions (deposit, shares deposit, reservation, claim).
- Custody changes are deterministic and rule-based.

### 6.2 Withdrawals Only From Free Balance
- Withdrawals can only debit free Points balances.
- Reserved balances cannot be withdrawn.

### 6.3 Withdrawal Backing
- Withdrawals must remain backed by protocol collateral reserves by construction.
- The protocol does not guarantee withdrawal in the same asset as deposit, only economic equivalence.

### 6.4 Claim Custody Is Temporary
- During claim, winning shares may be held in custody only for the duration required to redeem and credit Points.
- Claim cannot mint shares or Points out of nothing.

## 7. Meta-Transactions

### 7.1 Semantic Equivalence
- A signature-based call must have identical effects to a direct call by the recovered signer.

### 7.2 Replay Protection
- Each signed intent is usable at most once via per-user nonce enforcement.
- Nonce increments only on successful execution.

### 7.3 Domain Separation
- Signatures cannot be replayed across chains or across verifying contract addresses.

## 8. Administration, Pausing, and Upgrades

### 8.1 Pause Safety
- When paused, all state-changing operations are disabled.
- Pausing never modifies balances, obligations, or market state.

### 8.2 No Admin Fund Seizure
- No administrative action can arbitrarily move user balances.
- Admin control is limited to pausing, role/config management, and upgrades.

### 8.3 Upgrades Preserve Meaning
Upgrades must preserve:
- storage layout compatibility,
- accounting meaning of stored values,
- lifecycle derivation semantics,
- fee semantics and accrual separation.

Upgrades must not:
- invalidate existing balances,
- alter historical outcomes,
- bypass resolution rules.

## 9. Event Consistency (Observation Layer)

Events are not canonical, but must remain consistent with storage transitions.

- Events are emitted only after successful state changes.
- Events must not contradict on-chain storage.
- High-frequency events may prefer `UserId` to reduce gas, but must remain linkable to addresses via registry.

Event correctness is required for reliable indexing and UX but does not replace storage as the source of truth.
