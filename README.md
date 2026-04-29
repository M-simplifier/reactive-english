# Reactive English

Reactive English is a small full-stack English-learning web application built
with Haskell, PureScript, SQLite/PostgreSQL, and a custom PureScript FRP layer.

The app includes:

- a Servant backend with typed API payloads
- a PureScript browser frontend
- a generated Haskell/PureScript schema bridge
- local SQLite persistence
- production PostgreSQL support for Cloud Run
- Google Sign-In plus a local development login lane
- seeded A1-A2 English curriculum data
- backend EBT/PBT coverage and a small Lean proof workspace

This repository is public source for a running web app. Runtime credentials,
local databases, Terraform state, generated build outputs, and private planning
notes are intentionally not part of the public source tree.

## Repository Layout

- `backend/`: Haskell API server, persistence, auth, curriculum seeding
- `frontend/`: PureScript SPA and custom FRP runtime
- `schema-bridge/`: schema source and Haskell/PureScript code generator
- `curriculum/`: human-readable seeded lesson content
- `proof/`: Lean proof workspace for selected pure invariants
- `infra/terraform/`: GCP infrastructure for Cloud Run and Cloud SQL
- `.github/workflows/`: GitHub Actions deployment workflow

## Local Development

This project intentionally avoids Nix. Use `ghcup`, `cabal`, `node`, `npm`,
`purs`, and `spago`.

```sh
npm start
```

Then open `http://localhost:8080`.

On first startup, the script asks for `GOOGLE_CLIENT_ID` if it is not already
configured. Press Enter to run with the local dev login lane only.

## Verification

```sh
npm run assurance:check
npm run build
```

`assurance:check` runs schema generation, frontend tests, backend tests, and
Lean proofs.

## Visual Learning

This repository includes a local visual learning deck for understanding the
technical architecture, ADD posture, and GCP release path:

```sh
npm run learning:serve
```

Then open `http://localhost:8090`.

## Deployment

The production path uses Cloud Run, Artifact Registry, Cloud SQL for
PostgreSQL, Secret Manager, Terraform, and GitHub Actions with Workload Identity
Federation.

See [GCP Deployment](docs/deployment-gcp.md).

## License

No license is currently granted. Public visibility does not make this project
open source.
