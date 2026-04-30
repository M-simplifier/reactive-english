# syntax=docker/dockerfile:1

FROM haskell:9.6.7 AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
  && install -d /usr/share/keyrings \
  && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
    | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg \
  && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | gpg --dearmor -o /usr/share/keyrings/nodesource.gpg \
  && . /etc/os-release \
  && echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] https://apt.postgresql.org/pub/repos/apt ${VERSION_CODENAME}-pgdg main" \
    > /etc/apt/sources.list.d/pgdg.list \
  && echo "deb [signed-by=/usr/share/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" \
    > /etc/apt/sources.list.d/nodesource.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
    libpq-dev \
    nodejs \
    pkg-config \
    zlib1g-dev \
  && node --version \
  && npm --version \
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

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
  && install -d /usr/share/keyrings \
  && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
    | gpg --dearmor -o /usr/share/keyrings/postgresql.gpg \
  && . /etc/os-release \
  && echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] https://apt.postgresql.org/pub/repos/apt ${VERSION_CODENAME}-pgdg main" \
    > /etc/apt/sources.list.d/pgdg.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
    libpq5 \
    zlib1g \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /out/reactive-english-server /app/reactive-english-server
COPY --from=builder /app/frontend/dist /app/frontend/dist
COPY curriculum /app/curriculum

ENV PORT=8080
EXPOSE 8080

CMD ["/app/reactive-english-server", "--static-dir", "/app/frontend/dist", "--curriculum-path", "/app/curriculum/english-cefr-c2.json"]
