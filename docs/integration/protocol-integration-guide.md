# Social Wisdom - Protocol Integration Guide

## 0. Scope

This document explains how to integrate with the Social Wisdom protocol **from the outside**.

It is intended for:
- frontend applications,
- indexers,
- bots and market makers,
- analytics and monitoring systems.

This guide does **not** redefine protocol behavior.
All rules are defined by:
- `protocol-overview.md`
- `protocol-specification.md`
- `protocol-implementation.md`

This document focuses on:
- how to read protocol state,
- how to submit actions,
- how to reconstruct markets and order books,
- how to reason about UX flows.

## 1. High-Level Integration Model

At a high level, integration follows this pattern:

1. Discover protocol configuration.
2. Register / resolve user identity.
3. Read markets and their state.
4. Read order books and balances.
5. Submit transactions (trading, admin if applicable; claims are planned but not yet implemented).
6. Track events to stay in sync.

The protocol is fully on-chain and deterministic.

The external interface is split by domain:
- `IMarkets`, `ITrading`, `IAccounting`, `ICustody`, `IAdmin`
and aggregated by `IPlatform`.
There is no off-chain coordination layer required for correctness.

## 2. User Identity (UserId)

### 2.1 Address → UserId

The protocol internally operates on `UserId` for gas efficiency.

From an integration perspective:

- users are identified externally by `address`,
- internally by `userId`.

A `UserId` is assigned lazily.

**How to resolve UserId:**
- listen for `UserRegistered(address, userId)` events, or
- call the `userIdOf(address)` view.

Once assigned:
- a UserId never changes,
- mapping is permanent.

Frontends should cache `address ↔ userId`.

## 3. Markets

### 3.1 Discovering Markets

Markets are discovered via:
- `MarketCreated` events (canonical source),
- or paginated market views (if exposed).

From `MarketCreated` you obtain:
- `marketId`,
- `creatorId`,
- `resolverId`,
- lifecycle parameters,
- human-readable metadata (question, outcomes).

Human-readable strings are **not** stored on-chain beyond events.

---

### 3.2 Market State

Market state is **derived**, not stored.

To determine current state:
- call the market state derivation view,
- or re-derive off-chain using:
  - timestamps,
  - resolution flags,
  - finalized flag.

Never assume state from timestamps alone.
Resolution always overrides expiration.

## 4. Balances

### 4.1 Points Balances

For each user:
- free Points balance,
- reserved Points balance.

Free balance:
- withdrawable,
- usable for new orders.

Reserved balance:
- backing active obligations,
- not withdrawable.

Always show both in UI.

---

### 4.2 Outcome Shares

Outcome shares are tracked per:
- market,
- outcome,
- user.

Implementation note:
- shares balances are keyed by the Ask-side BookKey for the (market, outcome),
- Bid-side BookKeys are only for order books and are not used for share balances.

Frontends typically show:
- total shares per outcome,
- free vs reserved shares,
- winning vs non-winning shares after resolution.

## 5. Order Books

### 5.1 Reading the Order Book

Order books are reconstructed via views:

1. Fetch `asksMask` / `bidsMask` for a book.
2. Iterate ticks in priority order using the mask.
3. For each tick:
   - fetch level metadata (head, tail, totalShares),
   - traverse orders via linked list if needed.

This allows:
- depth charts,
- top-of-book,
- full FIFO reconstruction (if required).

---

### 5.2 Order Identification

Orders are identified by:
- `(bookKey, orderId)`.

OrderIds:
- are unique per book,
- monotonically increasing,
- never reused.

Never assume global uniqueness of orderId without bookKey.

## 6. Trading Flows

### 6.1 placeLimit

Typical UX flow:

1. User selects market, outcome, side.
2. User chooses price (tick) and quantity.
3. Frontend estimates:
   - required principal,
   - maximum trading fee.
4. Submit `placeLimit`.
5. Track:
   - `OrderPlaced`,
   - subsequent `Trade` events (if any).

Even if fully filled immediately:
- an `OrderPlaced` event is still emitted.

`placeLimit` always allocates and returns a new `orderId`.
If the order is fully filled immediately, it will not rest in the book (becomes inactive), but the `orderId` remains valid for indexing.

---

### 6.2 take (Market Order)

Typical UX flow:

1. User selects market, outcome, side.
2. User specifies:
   - quantity,
   - max acceptable price (`maxTick`),
   - minimum fill (`minFill`).
3. Submit `take`.
4. Track:
   - multiple `Trade` events,
   - final `Take` summary event.

If `minFill` is not satisfied, the transaction reverts.

---

### 6.3 Cancellation

To cancel an order:

1. Identify `(bookKey, orderId)`.
2. Call cancellation helper view to obtain predecessor candidates.
3. Submit `cancel` with candidate list.
4. Track `OrderCancelled`.

Cancellation is allowed in **all market states**.

## 7. Fees and UX Expectations

### 7.1 Trading Fees

- Fees are charged **in addition to** trade amounts.
- Price shown in UI is the execution price.
- Total cost = execution amount + fee.

Users:
- receive the full number of shares they trade for,
- pay fees separately from execution.

---

### 7.2 Winning Fees

Winning fees:
- are applied only at claim time,
- are deducted from the payout,
- never affect trading prices.

UI should show:
- gross payout,
- fee,
- net payout.

## 8. Resolution and Claims

### 8.1 Resolution Tracking

Resolution is tracked via events:

- `MarketResolved` - outcome selected (pending),
- `MarketFinalized` - outcome final.

Only after finalization can claims be executed (claim entrypoint is not yet implemented in the current contract).

---

### 8.2 Claims Flow

Claim UX is planned but not yet available on-chain.
Frontends should treat claims as unavailable until a claim entrypoint is introduced.

## 9. Deposits and Withdrawals

### 9.1 Deposits

Deposits:
- increase free Points balance,
- are independent of markets,
- may be performed at any time (unless paused).

UI should treat deposit as protocol-level, not market-level.

---

### 9.2 Withdrawals

Withdrawals:
- debit free Points balance,
- are backed by protocol collateral reserves,
- may not return the same asset as deposited.

Always check free balance before allowing withdrawal.

## 10. Events as the Sync Layer

Events are the primary sync mechanism for:

- frontend state,
- indexers,
- analytics.

Recommended approach:
- bootstrap state via views,
- stay in sync via events.

Events are **observational**, not authoritative.
Views define canonical state.

## 11. Meta-Transactions (Optional)

Meta-transactions are planned but not yet implemented in the current contract.

## 12. Integration Invariants

Integrations should assume:

- protocol behavior is deterministic,
- state transitions are explicit,
- events may be reordered within a transaction but not across transactions,
- views always reflect canonical state.

Never assume:
- resolver honesty,
- guaranteed liquidity,
- guaranteed profitability.

## 13. Final Notes

Social Wisdom is designed to be:
- transparent,
- explicit,
- mechanically predictable.

If something cannot be derived from:
- views,
- events,
- or explicit parameters,

then it is intentionally not part of the protocol contract.

All integration logic should be written with this assumption.
