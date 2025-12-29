# Social Wisdom — Smart Contracts (MVP)

This repository contains the smart contracts for the Social Wisdom prediction markets MVP.

The protocol is fully on-chain and implements a deterministic limit order book (price–time priority).
There is no backend.

## Quick links

- Architecture spec (source of truth): [docs/architecture/social-wisdom-mvp.md](docs/architecture/social-wisdom-mvp.md)

## What this repo includes

- On-chain order book (placeLimit / take / cancel)
- Shares custody (ERC-1155 outcome positions; Gnosis CTF adapter)
- Points accounting (free / reserved)
- Market lifecycle (create, resolve, enable payouts)
- Fee enforcement (trading fees + winning fee at claim time)
- Strict redemption gating (adapter callable only by `ORDER_BOOK`)

## What this repo does NOT include

- Frontend / UI
- Indexer
- Oracle implementation
- Backend-assisted matching
- AMM logic


## Canonical specification (source of truth)

This repository is spec-driven.

Read first:

- [docs/architecture/social-wisdom-mvp.md](docs/architecture/social-wisdom-mvp.md) — canonical architecture, storage layout, events, invariants

If contract code and documentation diverge, the architecture spec wins.

## Development rules (non-negotiable)

- Do not change storage layout without explicit migration planning.
- Do not remove typed keys or packed structs.
- Do not bypass redemption gating.
- Do not weaken lifecycle restrictions.
- Do not add privileged fund-moving paths.
- Always preserve listed invariants.


## Status

MVP. Correctness and determinism take precedence over gas optimization.


## License

See [LICENSE](LICENSE).
