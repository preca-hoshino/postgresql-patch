# Dockerfile - PostgreSQL + pgvector + 内置扩展
# Based on https://github.com/1Panel-dev/appstore/tree/dev/apps/postgresql
# Added: pgvector (向量搜索) + pg_stat_statements, pg_trgm, pgcrypto, hstore
#
# 用法:
#   docker build --build-arg PG_VERSION=18.4 --build-arg PGVECTOR_VERSION=0.8.2 -t postgresql-patch ./build

ARG PG_VERSION=18.4

# ===== Stage 1: Build pgvector extension =====
FROM postgres:${PG_VERSION}-alpine AS builder

ARG PG_VERSION=18.4
ARG PGVECTOR_VERSION=0.8.2

RUN apk add --no-cache \
        build-base \
        postgresql-dev \
        git \
    && sed -i 's/with_llvm[[:space:]]*=[[:space:]]*yes/with_llvm = no/g' /usr/local/lib/postgresql/pgxs/src/Makefile.global \
    && cd /tmp \
    && git clone --branch v${PGVECTOR_VERSION} --depth 1 https://github.com/pgvector/pgvector.git \
    && cd pgvector \
    && make OPTFLAGS="" -j$(nproc) \
    && make OPTFLAGS="" install \
    && mkdir -p /tmp/pgvector-build \
    && cp -a $(pg_config --sharedir)/extension/* /tmp/pgvector-build/ \
    && cp -a $(pg_config --pkglibdir)/vector*.so /tmp/pgvector-build/ \
    && echo "pgvector ${PGVECTOR_VERSION} built successfully"

# ===== Stage 2: Final image =====
FROM postgres:${PG_VERSION}-alpine

ARG PG_VERSION=18.4
ARG PGVECTOR_VERSION=0.8.2

LABEL maintainer="PostgreSQL pgvector Patch Community"
LABEL description="PostgreSQL ${PG_VERSION} + pgvector ${PGVECTOR_VERSION} + 内置扩展 — 基于 1Panel PostgreSQL 镜像"
LABEL org.opencontainers.image.title="PostgreSQL pgvector"
LABEL org.opencontainers.image.description="PostgreSQL ${PG_VERSION} + pgvector ${PGVECTOR_VERSION} + pg_stat_statements/pg_trgm/pgcrypto/hstore for 1Panel"
LABEL org.opencontainers.image.version="${PG_VERSION}-pgvector-${PGVECTOR_VERSION}"
LABEL pg.version="${PG_VERSION}"
LABEL pgvector.version="${PGVECTOR_VERSION}"

# Copy pgvector extension from builder
COPY --from=builder /tmp/pgvector-build/*.so /usr/local/lib/postgresql/
COPY --from=builder /tmp/pgvector-build/*.control /usr/local/share/postgresql/extension/
COPY --from=builder /tmp/pgvector-build/*.sql /usr/local/share/postgresql/extension/

# Enable pg_stat_statements in shared_preload_libraries (required for full functionality)
RUN sed -i "s/#shared_preload_libraries = ''/shared_preload_libraries = 'pg_stat_statements'/" \
        /usr/local/share/postgresql/postgresql.conf.sample \
    && echo "pg_stat_statements.track = all" >> /usr/local/share/postgresql/postgresql.conf.sample

# Copy init script to auto-create extensions
COPY init-pgvector.sh /docker-entrypoint-initdb.d/01-pgvector.sh

# Verify pgvector is loadable
RUN echo "=== pgvector installed ===" \
    && ls -la /usr/local/lib/postgresql/vector*.so \
    && ls -la /usr/local/share/postgresql/extension/vector*.control \
    && echo "pgvector ${PGVECTOR_VERSION} for PostgreSQL ${PG_VERSION} ready"
