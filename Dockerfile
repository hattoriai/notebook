# syntax=docker/dockerfile:1
#
# The Notebook release: its SQLite database and its uploads on a volume at
# /data.
#
#     docker build -t notebook .
#     docker run -p 4000:4000 -v notebook-data:/data \
#       -e PHX_HOST=notebook.example.com -e SECRET_KEY_BASE=... notebook
#
# Keep SECRET_KEY_BASE (or NOTEBOOK_VAULT_KEY) from run to run: the
# notebook's secrets are encrypted with it.

ARG ELIXIR_VERSION=1.20.1
ARG OTP_VERSION=29.0.2
ARG DEBIAN_VERSION=trixie-20260610-slim

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

# ===========================================================================
# Build: dependencies, assets and the release
# ===========================================================================
FROM ${BUILDER_IMAGE} AS build

RUN apt-get update -y && apt-get install -y build-essential git \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV

RUN mkdir config
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile
RUN mix assets.setup

COPY priv priv
COPY lib lib
COPY assets assets

RUN mix compile
RUN mix assets.deploy

# Changes to config/runtime.exs don't require recompiling the code.
COPY config/runtime.exs config/
COPY rel rel
RUN mix release

# ===========================================================================
# Runtime
# ===========================================================================
FROM ${RUNNER_IMAGE} AS runtime

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses6 locales ca-certificates && \
    apt-get clean && rm -f /var/lib/apt/lists/*_*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

RUN useradd --create-home app

# The database and the uploads live in /data. Mount a volume there to keep
# them. An empty named volume takes this directory's owner, so the app can
# write.
RUN mkdir -p /data/uploads && chown -R app:app /data
ENV NOTEBOOK_DATABASE=/data/notebook.db
ENV NOTEBOOK_UPLOADS=/data/uploads
VOLUME /data

WORKDIR /home/app
USER app

COPY --from=build --chown=app:app /app/_build/prod/rel/notebook ./

LABEL service="notebook"

ENV PHX_SERVER=true
ENV PORT=4000
EXPOSE 4000

CMD ["sh", "-c", "./bin/migrate && ./bin/notebook start"]
