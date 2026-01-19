# Social Wisdom - Protocol Overview

## 0. Scope and Status

This document defines the **conceptual model** of the Social Wisdom protocol.

It describes:
- core entities and terminology,
- market structure and lifecycle,
- trading mechanics,
- accounting units, custody, and fees,
- resolution rules.

It does not describe implementation details or optimizations.

All rules described here are enforced by the protocol.

## 1. Glossary and Terminology

This section defines all terms used throughout this document.
Each term has a single meaning and is used consistently.

---

### 1.1 Core Entities

**User**:

An externally owned account interacting with the protocol.

**Market**:

A prediction instance defined by a fixed set of outcomes, parameters, and lifecycle rules.

**Outcome**:

A mutually exclusive result of a market.

**Share (Outcome Share)**:

A claim on a specific outcome of a market.

**Winning Share**:

A share corresponding to the resolved winning outcome of a market.

---

### 1.2 Trading

**Order**:

A commitment by a user to trade outcome shares under specified conditions.

**Market Order**:

An order expressing intent to trade immediately against available liquidity.
Market orders attempt to fill up to a specified amount. If a minimum acceptable fill is not reached, the transaction reverts; otherwise, partial execution is allowed.

**Limit Order**:

An order placed with a specified price constraint.
Limit orders may execute immediately against existing liquidity within the acceptable price range. Any unfilled remainder is stored in the order book and executed later in order of creation.

**Maker**:

A user whose limit order adds liquidity to the order book.

**Taker**:

A user whose order consumes existing liquidity from the order book.

**Side**:

The direction of an order:
- **Ask** - selling outcome shares for Points.
- **Bid** - buying outcome shares for Points.

**Price (Tick)**:

The amount of Points paid per one outcome share.
Prices are natural numbers constrained to the range `[1, 99]` and typically correspond to cents of a settlement currency backing Points balances.

---

### 1.3 Accounting and Collateral

**Point (PTS)**:

An internal accounting unit used by the protocol.

**Collateral**:

Assets deposited into the protocol to support accounting balances and trading obligations.

**Free Balance**:

An accounting balance available for withdrawal or new orders.

**Reserved Balance**:

An accounting balance locked to collateralize open orders or active positions and unavailable for withdrawal.

---

### 1.4 Roles

**Market Creator**:

A user who creates and publishes a market by defining all its parameters, including outcomes, fees, and resolver.
Market creators do not receive special protocol permissions. They may receive a predefined share of fees as an economic incentive.

**Resolver**:

The authority responsible for selecting and finalizing the winning outcome of a market.

**Owner**:

An entity with protocol-level control, including emergency actions, fee exemptions, and upgrades to protocol logic via a proxy mechanism.

---

### 1.5 Fees and Settlement

**Trading Fee**:

A fee charged on trade execution, applied to makers, takers, or both.

**Winning Fee**:

A fee charged when redeeming winning shares during claim.

**Fee-Exempt Account**:

An account exempt from all protocol fees, including trading and winning fees.
Fee exemptions are managed by the Owner.

**Dust**:

Residual value resulting from rounding or discrete settlement that cannot be meaningfully attributed to a user.

## 2. System Overview

Social Wisdom is an **on-chain prediction market protocol**.

Users trade outcome shares against internal accounting units (Points) through a deterministic limit order book.
All matching, accounting, and settlement rules are enforced on-chain.

The protocol prioritizes:
- deterministic execution,
- explicit and inspectable rules,
- transparent economic behavior.

---

### 2.1 Outcome Representation

Outcome shares are implemented using a **thin wrapper around Gnosis Conditional Tokens (CTF)**.

This involves:
- deploying the Gnosis Conditional Tokens Framework contract (CTF),
- representing outcomes as ERC-1155 multi-token positions,
- mapping each outcome to a distinct token position.

The wrapper introduces minimal additional logic and primarily enforces:
- protocol custody constraints,
- gated redemption,
- integration with the trading and settlement flow.

---

## 3. Units of Value

### 3.1 Points (Accounting Units)

Points (PTS) are **internal accounting units** maintained by the protocol.

Points:
- are not tokens,
- are not transferable outside the protocol,
- do not represent an on-chain asset standard (e.g. ERC-20).

They are used exclusively to:
- express prices,
- settle trades,
- account for fees,
- represent claimable value upon market resolution.

For correct economic operation, Points are intended to be **economically backed by deposited collateral**, typically a stable-value asset.
The nature and custody of such collateral are abstracted at this level.

---

### 3.2 Deposits and Withdrawals

Users may deposit supported assets into the protocol to increase their free Points balance.

Deposits:
- convert deposited assets into an equivalent amount of Points,
- credit the resulting Points to the user's free balance,
- are subject to the set of assets supported by the protocol at the time of deposit.

Withdrawals:
- convert Points from the user's free balance back into the corresponding asset,
- are only permitted from free balances,
- are not permitted from reserved balances.

Deposits and withdrawals operate at the protocol level and are independent of individual markets.

---

### 3.3 Outcome Shares

Outcome shares represent claims on market outcomes.

- Only winning outcome shares have redemption value.
- Shares may be deposited into the protocol to enable trading.
- Custody is **temporary and purpose-specific**, limited to trading and settlement.

Outcome shares are not intended to be permanently held by the protocol.

## 4. Market Model

### 4.1 Market Definition

A market is created by a user (the market creator) with:
- a fixed number of outcomes,
- a designated resolver,
- fee parameters,
- lifecycle timestamps.

All market parameters are immutable after creation.

By interacting with a market, users explicitly accept the authority of its resolver.

At early stages of the protocol, market creation may be permissioned to mitigate reputational risk.

---

### 4.2 Market Lifecycle

Markets progress through the following phases.
At each phase, trading behavior and available actions are explicitly defined.

#### 1. Active

- Trading is enabled: users may place, match, and cancel orders.

#### 2. Expired

- Trading is disabled: new orders cannot be placed, and orders cannot be matched.
- Order cancellation is allowed to release reserved balances back into free balances.

#### 3. Resolved (Pending)

- A winning outcome is selected by the resolver.
- The resolution may still be modified.
- Trading remains disabled.
- Order cancellation remains allowed.

#### 4. Resolved (Ready)

- Resolution is final.
- Winning shares may be redeemed via claim.

## 5. Fees, Dust, and Incentives

### 5.1 Trading Fees

Markets may define:
- maker trading fees,
- taker trading fees.

Trading fees are charged in Points at trade execution.

For each trade:
- the traded amount is exchanged in full between counterparties,
- trading fees are charged **in addition to** the traded amount,
- fees are deducted from the users' free balances.

This ensures that users receive or sell the full intended trade amount, preserving intuitive UX.

Maker and taker fees are applied independently based on their respective roles in the trade.

---

### 5.2 Winning Fee

A winning fee may be charged when redeeming winning shares.

The winning fee:
- is applied only at claim time,
- is never applied during trading,
- does not influence price formation.

---

### 5.3 Market Creator Incentives

Market creators may receive a predefined share of **trading fees**.

- The share is defined by the protocol.
- Market creators do not control or modify fees after market creation.

This provides economic incentives without granting ongoing authority.

---

### 5.4 Fee Exemptions

Certain accounts may be fully exempt from:
- trading fees,
- winning fees.

Fee exemptions are global and managed by the Owner.
Implementations may key exemptions by `UserId` (resolved from address) as a storage optimization.
Dust handling is unaffected by fee exemptions.

---

### 5.5 Dust Handling

Due to discrete pricing and integer arithmetic, small residual amounts (“dust”) may arise during settlement.

Dust:
- cannot be reliably attributed to individual users,
- is accumulated in favor of the protocol,
- is expected to be negligible at the individual user level.

This prevents blocked claims and avoids unfair rounding behavior.

## 6. Trading Model

### 6.1 What Is Traded

Users trade **outcome shares against Points**.

The trade price:
- is expressed in Points per share,
- is a natural number in the range `[1, 99]`,
- typically corresponds to cents of a settlement currency backing Points balances.

---

### 6.2 Order Book

The protocol uses a **full limit order book**.

It supports:
- market orders with explicit fill constraints,
- limit orders,
- partial execution of limit orders.

Orders are matched strictly by:
1. best price,
2. order of creation among orders at the same price.

## 7. Custody and Collateralization

### 7.1 Trading Custody

Assets are held within the protocol to:
- back accounting balances,
- collateralize open orders,
- enable deterministic matching and settlement.

Balances are tracked as free or reserved.
Users may withdraw free balances whenever withdrawals are enabled.

---

### 7.2 Collateral Rules

All open trading positions must be fully collateralized.

- Buy orders reserve Points.
- Sell orders reserve outcome shares.

Reserved balances cannot be withdrawn until obligations are cleared.

## 8. Resolution Model

### 8.1 Resolver Authority

Each market has exactly one resolver.

The resolver:
- selects the winning outcome,
- may modify the resolution while pending,
- finalizes resolution by enabling payouts.

---

### 8.2 Resolution Finality

Once payouts are enabled:
- the outcome is final,
- no further changes are permitted,
- users may redeem winning shares.

## 9. Roles and Permissions

### 9.1 Owner

- emergency pause control,
- protocol logic upgrades via proxy,
- management of fee exemptions,
- no access to user funds,
- no control over market outcomes.

---

### 9.2 Market Creator

- creates and publishes markets,
- defines all market parameters at creation,
- has no post-creation powers.

---

### 9.3 Resolver

- authoritative outcome selection,
- no trading or fund access privileges.

## 10. Summary

Social Wisdom is a deterministic, on-chain prediction market protocol.

It trades outcome shares against internal accounting units via a strict limit order book,
enforces explicit lifecycle, custody, collateral, and fee rules,
and provides transparent economic incentives for all participants.

This document defines the complete conceptual model of the system.
