# Social Wisdom - Protocol Upgradability Specification

## 0. Scope

This document specifies how the Social Wisdom protocol is upgraded on-chain.

It defines:
- the proxy model used,
- upgrade authority and constraints,
- storage compatibility rules,
- and the invariants upgrades must preserve.

This document is intentionally narrow.
All behavioral rules remain defined by:
- `protocol-overview.md`
- `protocol-specification.md`
- `protocol-implementation.md`
- `protocol-invariants.md`

## 1. Upgradability Model

The protocol is deployed behind a **single upgradeable proxy**.

- The proxy holds **all persistent storage**.
- The implementation contract contains **all executable logic**.
- All external calls go through the proxy.

The proxy follows the **OpenZeppelin Transparent Upgradable Proxy** pattern.

## 2. Contracts Involved

### 2.1 PlatformProxy

The proxy contract:

- owns all protocol storage,
- delegates calls to the active implementation,
- exposes upgrade functionality to the admin (DEFAULT_ADMIN_ROLE / UPGRADER_ROLE).

The proxy itself contains:
- no business logic,
- no protocol rules,
- no accounting behavior.

---

### 2.2 Platform (Implementation)

The Platform contract:

- defines all protocol logic,
- assumes storage is already initialized in the proxy,
- must be storage-layout compatible with all previous versions.

Multiple Platform implementations may exist over time,
but only one is active at any given moment.

## 3. Upgrade Authority

Only accounts with **UPGRADER_ROLE** may perform upgrades.

Upgrade authority includes:
- upgrading the implementation address,
- performing optional initialization calls during upgrade.

Upgrade authority explicitly does **not** include:
- modifying user balances,
- resolving or finalizing markets,
- altering market parameters,
- bypassing lifecycle or fee rules.

## 4. Upgrade Process

A protocol upgrade consists of:

1. Deploying a new Platform implementation contract.
2. Verifying storage layout compatibility off-chain.
3. Calling `upgradeTo` (or `upgradeToAndCall`) on the proxy without `UPGRADER_ROLE`.
4. Optionally executing a post-upgrade initializer.

Upgrades are atomic at the proxy level.

## 5. Storage Compatibility Rules

All upgrades must obey strict storage rules.

### 5.1 Immutable Layout

- Existing storage slots must not be removed.
- Existing fields must not change meaning or type.
- Existing structs must not be reordered.
- Existing mappings must retain their key and value semantics.

---

### 5.2 Append-Only Extension

- New fields may only be appended to storage.
- New mappings may be added in unused storage slots.
- Gaps may be reserved explicitly for future use.

---

### 5.3 Identifier Stability

- All identifiers (UserId, MarketId, OrderId, keys) must retain their encoding.
- Bit layouts and shifts must never change.

## 6. Behavioral Preservation

An upgrade must preserve all protocol invariants.

Specifically, upgrades must not:

- change the meaning of balances (free vs reserved),
- invalidate existing orders or obligations,
- alter matching priority or execution rules,
- retroactively affect fees or settlements,
- change resolution semantics of existing markets.

Any change that would violate an invariant defined in
`protocol-invariants.md` is forbidden.

## 7. Initialization and Migration

If an upgrade introduces new storage fields:

- they must be initialized explicitly via an initializer,
- initialization must be idempotent or version-gated,
- initialization must not affect existing balances or obligations.

No implicit migrations are allowed.

## 8. Pausing and Upgrades

Upgrades may be performed:
- while the protocol is paused,
- or while it is unpaused.

Pausing does not change upgrade semantics.
Upgrading does not implicitly pause or unpause the protocol.

## 9. Failure Model

If an upgrade introduces incorrect logic:

- user funds remain in proxy storage,
- balances are not lost,
- a corrective upgrade may be deployed.

Upgradability exists to:
- reduce permanent failure risk,
- allow bug fixes and optimizations,
- preserve long-term protocol correctness.

## 10. Final Guarantees

The upgradability model guarantees that:

- protocol state survives all upgrades,
- user balances are not migrated or reset,
- historical data remains valid,
- the protocol can evolve without breaking invariants.

Upgrades change **how** the protocol executes,
never **what existing state means**.
