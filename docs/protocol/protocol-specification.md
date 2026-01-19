# Social Wisdom - Protocol Specification

## 0. Scope and Relationship to Protocol Overview

This document defines the **behavioral specification** of the Social Wisdom protocol.

It describes how the protocol behaves in key situations, how state transitions occur, and how economic flows are handled.

This specification builds on the Protocol Overview:
- the Overview defines *what the system is*,
- this document defines *how it behaves*.

If the two documents appear to diverge, the Overview defines intent and meaning, while this specification clarifies concrete behavior.

This document is implementation-agnostic and does not prescribe storage layout, contract structure, or gas optimizations.

## 1. System Model

This section describes the protocol's **mental model** - how the system fits together conceptually.

### 1.1 Core Model

At a high level:

- Users hold **Points** and **outcome shares**.
- Markets define which outcomes exist and how they are resolved.
- An order book defines how shares are exchanged for Points.
- Resolution converts winning outcome shares into claimable value.

The protocol functions as:
- a deterministic matching engine for trades,
- a custodian for trading- and settlement-related balances,
- a settlement layer for resolved markets.

---

### 1.2 Value Flow

Value moves through the protocol as follows:

1. A user deposits supported assets into the protocol.
2. The deposit increases the user's **free Points balance**.
3. When trading, Points or shares are temporarily moved into **reserved balance**.
4. Trades exchange shares and Points between users.
5. After resolution, winning shares become redeemable and claims convert them into Points.
6. Free Points may be withdrawn back into supported assets.

The protocol never creates value out of nothing; all Points and claims are derived from deposited collateral or explicit exchanges between users.

---

### 1.3 Determinism and Explicit Rules

The protocol is deterministic, explicit, and state-driven.

Given the same inputs and state, it always produces the same outcomes. All state transitions are governed by explicit rules and require no off-chain coordination.

This design favors predictability, auditability, and user trust over flexibility and short-term UX optimizations.

---

### 1.4 Authority Boundaries

Responsibilities are clearly separated:

- **Users** decide what to trade and when.
- **Market creators** define markets but do not control them afterward.
- **Resolvers** select outcomes for their markets.
- **The protocol** enforces rules and settlement mechanically.

No single actor can arbitrarily move user funds, bypass accounting rules, or alter market parameters after creation.

## 2. Accounting and Balances

The protocol tracks value using an explicit accounting model designed to ensure full collateralization and prevent implicit leverage.

---

### 2.1 Balance Types

For each user, balances in Points and outcome shares are tracked as:

- **Free balance** - available for withdrawal or for creating new obligations.

- **Reserved balance** - locked to satisfy an active obligation and unavailable for withdrawal.

The sum of free and reserved balances represents the user's total balance.

---

### 2.2 Balance Reservation

Balances move from free to reserved when a user creates an obligation that depends on them.

Examples include:
- placing a bid order, which reserves Points,
- placing an ask order, which reserves outcome shares.

All obligations must be fully collateralized. Partially collateralized obligations are not permitted.

---

### 2.3 Balance Release

Reserved balances return to free balance when the corresponding obligation is cleared.

This occurs when:
- an order is fully filled,
- an order is cancelled (with or without partial execution),
- a market enters a state where obligations are no longer valid.

Balance release is explicit and deterministic.

---

### 2.4 Prohibited States

The protocol forbids:
- negative balances,
- obligations without sufficient collateral,
- simultaneous use of the same balance as both free and reserved,
- withdrawal of reserved balances.

---

### 2.5 Rationale

Separating balances into free and reserved categories enforces strict collateralization, simplifies safety reasoning, and provides clear UX expectations.

## 3. Markets and Lifecycle

Markets define the scope for trading and resolution. Market state determines which actions are available at any time.

---

### 3.1 Market Creation

A market is created by specifying:
- a fixed set of outcomes,
- a designated resolver,
- fee parameters,
- lifecycle timestamps and rules.

All parameters are immutable after creation. Once created, the market exists independently of its creator.

At early stages, market creation may be permissioned to mitigate reputational and operational risk.

---

### 3.2 Market States

Each market exists in exactly one state at any time:

- **Active**
- **Expired**
- **Resolved (Pending)**
- **Resolved (Final)**

Not all markets necessarily pass through every state.

---

### 3.2.1 Active

The **Active** state represents the normal trading phase.

- Users may place, match, and cancel orders.
- New trading obligations may be created.

The market remains Active until either its activity window expires or the resolver provides an outcome.

---

### 3.2.2 Expired

The **Expired** state represents a market whose trading period has ended without a finalized outcome.

This state exists only if explicitly configured.

- Existing orders may be cancelled to release reserved balances.

Expired markets wait for the resolver to provide an outcome. Markets resolved before expiration transition directly from Active to Resolved (Pending).

---

### 3.2.3 Resolved (Pending)

The **Resolved (Pending)** state begins once the resolver provides an outcome.

- A winning outcome is defined but not final.
- Orders may still be cancelled.

This state supports future extensions such as dispute resolution or delayed finality.

---

### 3.2.4 Resolved (Final)

The **Resolved (Final)** state is terminal.

- The winning outcome is immutable.
- Winning shares become redeemable.
- Claims may be executed.

---

### 3.3 Rationale

Explicit lifecycle states separate trading, waiting, and settlement phases and ensure settlement occurs only against definitive outcomes.

## 4. Trading and Order Matching

Trading occurs through a deterministic limit order book.

---

### 4.1 What Is Traded

Users trade **outcome shares for Points** at discrete prices expressed as Points per share.

---

### 4.2 Order Types

The protocol supports **market orders** and **limit orders**.

Both specify:
- a side (Ask or Bid),
- a quantity of outcome shares,
- optional execution constraints.

---

#### 4.2.1 Market Orders

Market orders attempt immediate execution against available liquidity.

- They may execute across multiple price levels.
- A minimum fill constraint applies.

If the minimum fill is not met, the transaction reverts. Market orders never rest in the order book.

---

#### 4.2.2 Limit Orders

Limit orders specify a price constraint.

- They may execute immediately within the acceptable price range.
- Any unfilled remainder rests in the order book.

---

### 4.3 Ask and Bid Semantics

- **Ask** - selling outcome shares for Points (reserves shares).
- **Bid** - buying outcome shares with Points (reserves Points).

All resting orders are fully collateralized.

---

### 4.4 Matching Rules

Orders are matched deterministically by:
1. **Price priority** - better prices match first.
2. **Time priority** - earlier orders at the same price match first.

---

### 4.5 Partial Execution and Cancellation

Orders may be partially executed depending on available liquidity.

Resting limit orders may be cancelled when allowed by market state. Cancellation clears remaining obligations and releases reserved balances.

---

### 4.6 Rationale

A deterministic limit order book ensures predictable execution, fair ordering, and transparent price formation.

## 5. Fees and Economic Flows

Fees are explicit, predictable, and applied outside of price formation.

---

### 5.1 Fee Types

- **Trading fees** - applied to executed trades.
- **Winning fees** - applied when redeeming winning shares.

All fees are denominated in Points. Some accounts may be fee-exempt.

---

### 5.2 Trading Fees

Trading fees may differ for makers and takers.

When an order is placed, the maximum applicable trading fee is reserved along with the principal obligation.

- Reserved fees represent a potential obligation.
- Fees are charged only on actual execution.
- Cancelled or unexecuted orders release reserved fees.

Executed trades exchange the full traded amount; fees are charged in addition and do not affect execution price.

---

### 5.3 Winning Fee

Winning fees are applied atomically at claim time.

- The fee is deducted from the gross payout.
- It is never reserved or charged during trading.

---

### 5.4 Market Creator Incentives

Market creators may receive a predefined share of **trading fees**. They do not control fees after creation.

---

### 5.5 Fee Exemptions and Dust

Fee exemptions apply globally and do not affect matching rules. Implementation may key exemptions by `UserId` (resolved from address via the registry) as a storage optimization.

Residual rounding amounts (“dust”) may arise during settlement and are accumulated by the protocol.

---

### 5.6 Rationale

Separating trading and winning fees ensures users are charged only for realized actions and keeps price formation clean.

## 6. Resolution and Claims

Resolution determines the winning outcome; claims realize value.

---

### 6.1 Resolver Authority

Each market has a single resolver.

Resolvers:
- select and finalize outcomes,
- have no access to user balances,
- cannot bypass accounting or fee rules.

---

### 6.2 Resolution Phases

Resolution occurs in two phases:
- **Resolved (Pending)**
- **Resolved (Final)**

This separates outcome provision from finality.

---

### 6.3 Claims

Claims are available only after final resolution.

When a claim is executed:
- winning shares are redeemed,
- the gross payout is calculated,
- the winning fee is deducted,
- net Points are credited to the user's free balance.

---

### 6.4 Rationale

Delayed finality enables future dispute mechanisms and ensures settlement occurs only against definitive outcomes.

## 7. Deposits, Withdrawals, and Custody

The protocol may assume custody of assets as required by its rules.

---

### 7.1 Deposits

Deposits convert supported assets into Points and credit the user's free balance. Deposits are independent of markets.

---

### 7.2 Withdrawals

Withdrawals redeem Points from free balance into economically equivalent value.

Withdrawals are backed by protocol reserves but are not guaranteed to use the original deposit asset.

---

### 7.3 Custody

Assets enter custody only through protocol-defined actions and may be used by the protocol as permitted by its rules.

Custody applies during trading, settlement, and claims, and persists only as long as required.

---

### 7.4 Rationale

This model enforces deterministic settlement while keeping custody explicit and limited.

## 8. Safety Guarantees and Design Choices

### 8.1 Safety Guarantees

The protocol guarantees:
- deterministic execution,
- full collateralization of obligations,
- absence of hidden leverage,
- explicit custody boundaries,
- predictable settlement rules.

---

### 8.2 Deliberate Non-Guarantees

The protocol does not guarantee:
- correctness of outcomes,
- resolver honesty,
- participant profitability,
- continuous liquidity,
- availability of specific withdrawal assets.

---

### 8.3 Design Choices

Key choices include:
- determinism over flexibility,
- on-chain enforcement,
- separation of trading, resolution, and settlement,
- minimal implicit behavior.

---

### 8.4 Closing Notes

This specification defines the behavioral contract of the Social Wisdom protocol.

Together with the Protocol Overview, it defines the complete conceptual and behavioral model of the system.
