# Social Wisdom Protocol

Social Wisdom is an on-chain prediction market protocol with a deterministic limit order book, explicit lifecycle rules, and fully collateralized trading.

This repository contains the **formal documentation** defining the protocol’s behavior, implementation model, invariants, and integration surface.

The documents are designed to be:
- explicit and non-ambiguous,
- implementation-oriented,
- free of marketing language,
- suitable for auditing, implementation, and long-term maintenance.

## Documentation Structure

All protocol documentation lives in `/docs`.

### 1. Protocol Overview

**`/docs/protocol/protocol-overview.md`**

High-level conceptual description of the system.

Defines:
- core entities and terminology,
- what markets, orders, shares, and Points are,
- custody, fees, and resolution at a conceptual level,
- the mental model of how value flows through the protocol.

This is the entry point for understanding *what the protocol is*.

### 2. Protocol Specification

**`/docs/protocol/protocol-specification.md`**

Behavioral specification of the protocol.

Defines:
- allowed and disallowed actions,
- market lifecycle and state transitions,
- trading semantics and order matching rules,
- fee application and settlement behavior,
- deposits, withdrawals, and custody rules.

This document defines *how the protocol behaves* in all key situations.

### 3. Protocol Implementation

**`/docs/implementation/protocol-implementation.md`**

Concrete on-chain design and smart contract architecture.

Defines:
- contract structure and responsibilities,
- storage layout and packing,
- identifiers, keys, and encoding schemes,
- order book internals,
- trading APIs and internal flows,
- fee accounting,
- events,
- meta-transactions,
- pausing, administration, and upgrade mechanics.

This document defines *how the protocol is implemented on-chain*.

### 4. Protocol Invariants

**`/docs/protocol/protocol-invariants.md`**

A compact, authoritative list of invariants aggregated from all other documents.

Defines:
- accounting and collateralization guarantees,
- order book correctness conditions,
- lifecycle and resolution guarantees,
- fee and custody safety properties,
- upgrade and admin constraints.

Any violation of an invariant is a correctness or security bug.

### 5. Protocol Upgradability Specification

**`/docs/protocol/protocol-upgradability-specification.md`**

Defines the proxy-based upgrade model.

Covers:
- proxy architecture,
- upgrade authority,
- storage compatibility rules,
- behavioral preservation requirements,
- constraints on upgrades.

This document defines *how the protocol can evolve safely*.

### 6. Protocol Integration Guide

**`/docs/integration/protocol-integration-guide.md`**

Guide for external consumers.

Intended for:
- frontends,
- bots and market makers,
- indexers and analytics systems.

Explains:
- how to read state via views and events,
- how to reconstruct markets and order books,
- how to submit trades, cancellations, claims,
- UX expectations around fees, resolution, and balances.

This document defines *how to work with the protocol from the outside*.

## Reading Order (Recommended)

1. `protocol-overview.md`
2. `protocol-specification.md`
3. `protocol-implementation.md`
4. `protocol-invariants.md`
5. `protocol-upgradability-specification.md`
6. `protocol-integration-guide.md`

## Design Philosophy (Brief)

- Deterministic execution
- Explicit state transitions
- Full collateralization
- No implicit behavior
- No hidden leverage
- Clear custody boundaries
- Upgradeable without breaking invariants

If a rule is not explicitly defined in these documents, it is intentionally not part of the protocol.

## Status

Documentation reflects the **current intended protocol design**.

Implementation must conform to:
- the specification,
- the invariants,
- and the upgradability constraints.

## License

See [LICENSE](LICENSE).
