# syntax=docker/dockerfile:1

FROM haskell:9.8.4 AS builder

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    libpq-dev \
    nodejs \
    npm \
    pkg-config \
    zlib1g-dev \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY cabal.project package.json package-lock.json ./
COPY backend/reactive-english.cabal backend/reactive-english.cabal
COPY schema-bridge/schema-bridge.cabal schema-bridge/schema-bridge.cabal
COPY frontend/package.json frontend/package-lock.json frontend/spago.yaml frontend/spago.lock frontend/

RUN cabal update \
  && cabal build all -fpostgres --only-dependencies \
  && npm --prefix frontend ci

COPY . .

RUN cabal run schema-bridge -- backend/src/ReactiveEnglish/Schema/Generated.hs frontend/src/App/Schema/Generated.purs \
  && npm --prefix frontend run build \
  && cabal build exe:reactive-english-server -fpostgres \
  && mkdir -p /out \
  && cp "$(cabal list-bin exe:reactive-english-server -fpostgres)" /out/reactive-english-server

FROM debian:bookworm-slim AS runtime

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    libpq5 \
    zlib1g \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /out/reactive-english-server /app/reactive-english-server
COPY --from=builder /app/frontend/dist /app/frontend/dist
COPY curriculum /app/curriculum

ENV PORT=8080
EXPOSE 8080

CMD ["/app/reactive-english-server", "--static-dir", "/app/frontend/dist", "--curriculum-path", "/app/curriculum/english-a2.json"]
