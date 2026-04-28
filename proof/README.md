# Proof Workspace

This directory contains the Lean proof artifacts for the extracted assurance
kernel.

## Scope

The proof target is intentionally narrow:

- scalar progression rules
- spaced-review monotonicity
- completion decision invariants
- lesson status case splits
- Google token acceptance and expiry invariants for the extracted auth
  validation kernel
- a small streak-advancement model
- the Ordering fragment-presentation contract: shuffled banks must remain
  permutations of the canonical bank
- the vocabulary review scalar kernel: bounded mastery, allowed/monotone
  review-hour buckets, and positive dimension XP deltas

It is not a proof of the whole running web application.

## Build

From the repository root:

```sh
./scripts/build-proofs.sh
```

This bootstraps a repo-local `elan` installation under `.tooling/` and then
builds the Lean workspace in `proof/`.

## Main Files

- [ReactiveEnglishProof.lean](ReactiveEnglishProof.lean)
- [ReactiveEnglishProof/Rules.lean](ReactiveEnglishProof/Rules.lean)

## Auth Boundary Note

The proof does not model Aeson, HTTP, Google, cookies, or SQLite. It proves pure
rules used after external data has already been decoded and normalized:
accepted Google token claims imply accepted issuer, accepted audience, accepted
expiry, and verified email; past expiry timestamps are rejected; present/future
expiry timestamps are accepted.

For randomization, the proof does not model the entropy source. It models the
post-entropy contract: a presented Ordering fragment bank that is a permutation
of the canonical bank preserves length and membership, and a non-canonical
presentation is explicitly not the original order.

For vocabulary review, the proof does not model curriculum authoring, SQLite
queries, or learner text normalization. It proves the scalar scheduler and XP
facts used after the backend has built a typed review prompt.
