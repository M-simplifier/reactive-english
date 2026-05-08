# Reactive English

Reactive English is a small full-stack English-learning web application built
with Haskell, PureScript, SQLite, and a custom PureScript FRP layer.

The app includes:

- a Servant backend with typed API payloads
- a PureScript browser frontend
- a generated Haskell/PureScript schema bridge
- local SQLite persistence
- Google Sign-In plus a local development login lane
- seeded A1-C2 English curriculum data
- an A1-C2 placement test that can unlock the right starting band
- backend EBT/PBT coverage and a small Lean proof workspace

This repository is kept public as a reference artifact for full-stack functional
web app development, custom FRP state management, generated Haskell/PureScript
payload schemas, and assurance-driven development with Type/EBT/PBT/Proof
layers. Operational deployment assets have been removed. Runtime credentials,
local databases, generated build outputs, and private planning notes are
intentionally not part of the public source tree.

## Repository Layout

- `backend/`: Haskell API server, persistence, auth, curriculum seeding
- `frontend/`: PureScript SPA and custom FRP runtime
- `schema-bridge/`: schema source and Haskell/PureScript code generator
- `curriculum/`: human-readable seeded lesson content
- `proof/`: Lean proof workspace for selected pure invariants

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
npm run curriculum:generate
npm run assurance:check
npm run build
```

`curriculum:generate` regenerates the checked-in CEFR seed. `assurance:check`
runs schema generation, frontend tests, backend tests, and Lean proofs.

## License

No license is currently granted. Public visibility does not make this project
open source.
